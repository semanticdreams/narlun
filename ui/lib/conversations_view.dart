import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'appbar_avatar.dart';
import 'avatar_image.dart';
import 'frontend_error_reporter.dart';
import 'http.dart';
import 'invite_qr_button.dart';
import 'install_prompt_actions.dart';
import 'install_prompt_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'messages_view.dart';
import 'models.dart';
import 'push_notifications_service.dart';
import 'route_utils.dart';
import 'session_actions.dart';
import 'websocket.dart';

class ConversationsView extends StatefulWidget {
  final HttpService? httpService;
  final WebsocketService? websocketService;
  final bool showChrome;
  final VoidCallback? onOpenNearby;
  final int? initialRoomIdToOpen;

  const ConversationsView({
    super.key,
    this.httpService,
    this.websocketService,
    this.showChrome = true,
    this.onOpenNearby,
    this.initialRoomIdToOpen,
  });

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
  bool _pushPromptEligible = false;
  bool _loadingInitialRooms = true;
  bool _openedInitialRoom = false;
  bool _reportedMissingInitialRoom = false;
  bool _reportedPromptEligibility = false;
  bool _reportedPushPromptVisible = false;
  bool _reportedInstallPromptVisible = false;

  void _showRefreshFailure(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> updateRooms({bool silentErrors = false}) async {
    logFrontendDiagnostic(
      'rooms_refresh_started',
      'Started refreshing room summaries.',
      details: {
        'silent_errors': silentErrors,
        'initial_room_id_to_open': widget.initialRoomIdToOpen,
      },
    );
    try {
      final resp = await httpService.get_rooms(silentErrors: silentErrors);
      if (!mounted) {
        return;
      }
      setState(() {
        rooms
          ..clear()
          ..addAll(resp);
        _loadingInitialRooms = false;
      });
      logFrontendDiagnostic(
        'rooms_refresh_completed',
        'Finished refreshing room summaries.',
        details: {
          'silent_errors': silentErrors,
          'room_count': rooms.length,
          'room_ids': rooms.take(10).map((room) => room.id).toList(),
        },
      );
      unawaited(_openInitialRoomIfNeeded());
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
      logFrontendDiagnostic(
        'rooms_refresh_failed',
        'Refreshing room summaries failed.',
        details: {'silent_errors': silentErrors},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingInitialRooms = false;
      });
      _showRefreshFailure('Could not refresh rooms. Trying again soon.');
    }
  }

  Future<void> _openInitialRoomIfNeeded() async {
    final roomId = widget.initialRoomIdToOpen;
    if (_openedInitialRoom || roomId == null || !mounted) {
      return;
    }
    final currentUser = Provider.of<MeModel>(context, listen: false).data;
    if (currentUser == null || !currentUser.authenticated) {
      return;
    }
    RoomSummary? room;
    for (final candidate in rooms) {
      if (candidate.id == roomId) {
        room = candidate;
        break;
      }
    }
    if (room == null) {
      if (!_loadingInitialRooms && !_reportedMissingInitialRoom) {
        _reportedMissingInitialRoom = true;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('That invite room is no longer available.'),
          ),
        );
      }
      return;
    }
    _openedInitialRoom = true;
    final roomDeleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => MessagesView(
          room: room!,
          me: currentUser,
          httpService: httpService,
          websocketService: websocketService,
        ),
      ),
    );
    if (roomDeleted == true && mounted) {
      await updateRooms();
    }
  }

  @override
  void initState() {
    super.initState();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    httpService =
        widget.httpService ?? Provider.of<HttpService>(context, listen: false);
    installSuggestionTimer = Timer(_installSuggestionDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _installSuggestionEligible = true;
        _pushPromptEligible = true;
      });
      _reportPromptEligibility();
    });
    unawaited(updateRooms(silentErrors: true));
    unawaited(websocketService.ensureConnected());
    roomsChangedSubscription = websocketService.roomsChangedStream().listen(
      (_) => unawaited(updateRooms(silentErrors: true)),
    );
    connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) {
      if (event == 'reconnected') {
        unawaited(updateRooms(silentErrors: true));
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

  void _reportPromptEligibility() {
    if (_reportedPromptEligibility) {
      return;
    }
    _reportedPromptEligibility = true;
    logFrontendDiagnostic(
      'conversation_prompts_eligible',
      'Conversation prompt suggestions became eligible.',
      details: {
        'install_eligible': _installSuggestionEligible,
        'push_eligible': _pushPromptEligible,
      },
    );
  }

  void _reportPromptVisibility({
    required bool pushVisible,
    required bool installVisible,
  }) {
    if (pushVisible && !_reportedPushPromptVisible) {
      _reportedPushPromptVisible = true;
      logFrontendDiagnostic(
        'conversation_push_prompt_visible',
        'Conversation screen displayed the push notification prompt.',
      );
    }
    if (installVisible && !_reportedInstallPromptVisible) {
      _reportedInstallPromptVisible = true;
      logFrontendDiagnostic(
        'conversation_install_prompt_visible',
        'Conversation screen displayed the install prompt.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Consumer3<MeModel, InstallPromptService, PushNotificationsService>(
      builder: (context, meModel, installPromptService, pushService, child) {
        final currentUser = meModel.data;
        final pushPromptVisible =
            currentUser?.authenticated == true &&
            _pushPromptEligible &&
            pushService.shouldShowPrompt;
        final installPromptVisible =
            currentUser?.authenticated == true &&
            _installSuggestionEligible &&
            installPromptService.shouldShowSuggestion;
        _reportPromptVisibility(
          pushVisible: pushPromptVisible,
          installVisible: installPromptVisible,
        );
        return ListView(
          children: [
            if (pushPromptVisible)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Turn On Notifications',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Get notified about new messages even when Narlun is not open.',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: pushService.isBusy
                                  ? null
                                  : () async {
                                      try {
                                        await pushService.enableNotifications();
                                      } catch (error) {
                                        if (!mounted) {
                                          return;
                                        }
                                        if (isAlreadyPresentedActionError(
                                          error,
                                        )) {
                                          return;
                                        }
                                        _showRefreshFailure(
                                          describeActionError(
                                            error,
                                            fallbackDescription:
                                                'Could not enable notifications right now.',
                                          ),
                                        );
                                      }
                                    },
                              child: const Text('Turn on'),
                            ),
                            TextButton(
                              onPressed: pushService.dismissPrompt,
                              child: const Text('Not now'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (installPromptVisible)
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
            if (_loadingInitialRooms)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No rooms yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Start from Nearby to discover people around you and open your first conversation.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed:
                              widget.onOpenNearby ??
                              () {
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/nearby',
                                );
                              },
                          child: const Text('Find people nearby'),
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
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(timeago.format(room.updatedAt)),
                      if (room.pendingJoinRequestCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${room.pendingJoinRequestCount} request${room.pendingJoinRequestCount == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                      if (room.pushMuted)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.notifications_off_outlined,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
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
                              settings: RouteSettings(
                                name: roomsRouteWithOpenRoom(room.id),
                              ),
                              builder: (context) => MessagesView(
                                room: room,
                                me: currentUser,
                                httpService: httpService,
                                websocketService: websocketService,
                              ),
                            ),
                          );
                          if (roomDeleted == true) {
                            await updateRooms();
                          }
                        },
                ),
              ),
          ],
        );
      },
    );

    if (!widget.showChrome) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: const [InviteQrButton(), AppBarAvatar()],
      ),
      body: content,
    );
  }
}
