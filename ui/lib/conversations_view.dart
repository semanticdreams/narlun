import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'appbar_avatar.dart';
import 'avatar_image.dart';
import 'http.dart';
import 'install_prompt_actions.dart';
import 'install_prompt_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'messages_view.dart';
import 'models.dart';
import 'session_actions.dart';
import 'websocket.dart';

class ConversationsView extends StatefulWidget {
  final HttpService? httpService;
  final WebsocketService? websocketService;

  const ConversationsView({Key? key, this.httpService, this.websocketService})
    : super(key: key);

  @override
  State<ConversationsView> createState() => _ConversationsState();
}

class _ConversationsState extends State<ConversationsView> {
  static const _installSuggestionDelay = Duration(seconds: 8);

  late final WebsocketService websocketService;
  late final HttpService httpService;

  final List<RoomSummary> rooms = [];
  StreamSubscription? roomsChangedSubscription;
  StreamSubscription? connectionEventsSubscription;
  Timer? installSuggestionTimer;
  bool _installSuggestionEligible = false;

  void _showRefreshFailure(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> update_rooms({bool silentErrors = false}) async {
    try {
      final resp = await httpService.get_rooms(silentErrors: silentErrors);
      if (!mounted) {
        return;
      }
      setState(() {
        rooms
          ..clear()
          ..addAll(resp);
      });
    } on UnauthorizedResponse {
      if (!mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session is no longer valid. Please sign in again.',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showRefreshFailure('Could not refresh rooms. Trying again soon.');
    }
  }

  @override
  void initState() {
    super.initState();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    httpService =
        widget.httpService ??
        Provider.of<HttpService>(context, listen: false);
    installSuggestionTimer = Timer(_installSuggestionDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _installSuggestionEligible = true;
      });
    });
    unawaited(update_rooms(silentErrors: true));
    unawaited(websocketService.ensureConnected());
    roomsChangedSubscription = websocketService.roomsChangedStream().listen(
      (_) => unawaited(update_rooms(silentErrors: true)),
    );
    connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) {
      if (event == 'reconnected') {
        unawaited(update_rooms(silentErrors: true));
      }
    });
  }

  @override
  void dispose() {
    installSuggestionTimer?.cancel();
    roomsChangedSubscription?.cancel();
    connectionEventsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms'), actions: const [AppBarAvatar()]),
      body: Consumer2<MeModel, InstallPromptService>(
        builder: (context, meModel, installPromptService, child) {
          final currentUser = meModel.data;
          return ListView(
            children: [
              if (currentUser?.authenticated == true &&
                  _installSuggestionEligible &&
                  installPromptService.shouldShowSuggestion)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Install Narlun',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add Narlun to your home screen for faster launch and a more app-like chat experience.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: () {
                                  unawaited(
                                    handleInstallRequest(
                                      context,
                                      installPromptService,
                                    ),
                                  );
                                },
                                child: const Text('Install app'),
                              ),
                              TextButton(
                                onPressed: installPromptService.dismissSuggestion,
                                child: const Text('Not now'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              for (final room in rooms)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ListTile(
                    key: ValueKey('room-${room.id}'),
                    leading: AvatarImage(
                      picture: currentUser == null
                          ? room.picture
                          : room.displayPictureFor(currentUser),
                    ),
                    trailing: Text(timeago.format(room.updatedAt)),
                    title: Text(
                      currentUser == null
                          ? (room.name ?? '')
                          : room.displayTitleFor(currentUser),
                    ),
                    subtitle: Text(room.lastMessage?.body ?? ''),
                    onTap: currentUser == null
                        ? null
                        : () async {
                            final roomDeleted = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    MessagesView(room: room, me: currentUser),
                              ),
                            );
                            if (roomDeleted == true) {
                              await update_rooms();
                            }
                          },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
