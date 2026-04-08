import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'appbar_avatar.dart';
import 'avatar_image.dart';
import 'frontend_error_reporter.dart';
import 'http.dart';
import 'invite_qr_button.dart';
import 'locator.dart';
import 'me_model.dart';
import 'messages_view.dart';
import 'models.dart';
import 'rooms_feed_model.dart';
import 'route_utils.dart';
import 'session_actions.dart';
import 'websocket.dart';

class ConversationsView extends StatefulWidget {
  final HttpService? httpService;
  final WebsocketService? websocketService;
  final bool showChrome;
  final VoidCallback? onOpenNearby;
  final int? initialRoomIdToOpen;
  final RoomsFeedModel? roomsFeedModel;
  final bool enableRealtimeRoomSummarySync;
  final VoidCallback? onCreateRoom;

  const ConversationsView({
    super.key,
    this.httpService,
    this.websocketService,
    this.showChrome = true,
    this.onOpenNearby,
    this.initialRoomIdToOpen,
    this.roomsFeedModel,
    this.enableRealtimeRoomSummarySync = true,
    this.onCreateRoom,
  });

  @override
  State<ConversationsView> createState() => _ConversationsState();
}

class _ConversationsState extends State<ConversationsView> {
  MeModel? _meModel;
  late final WebsocketService websocketService;
  late final HttpService httpService;
  late final RoomsFeedModel roomsFeedModel;
  bool _ownsRoomsFeedModel = false;
  StreamSubscription? roomsChangedSubscription;
  StreamSubscription? connectionEventsSubscription;
  bool _openedInitialRoom = false;
  bool _reportedMissingInitialRoom = false;

  String _lastMessagePreview(RoomSummary room, SessionUser? currentUser) {
    final preview = room.lastMessage;
    if (preview == null || preview.body.isEmpty) {
      return '';
    }
    final shouldShowSender = currentUser == null
        ? room.participants.length > 2
        : room.otherParticipantsFor(currentUser).length > 1;
    if (shouldShowSender &&
        preview.senderUsername != null &&
        preview.senderUsername!.isNotEmpty &&
        preview.senderId != currentUser?.id) {
      return '${preview.senderUsername}: ${preview.body}';
    }
    return preview.body;
  }

  void _showRefreshFailure(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _ensureWarmRooms() async {
    try {
      await roomsFeedModel.ensureWarm(silentErrors: true);
      await _openInitialRoomIfNeeded();
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
      if (!mounted || roomsFeedModel.hasCachedData) {
        return;
      }
      _showRefreshFailure('Could not refresh rooms. Trying again soon.');
    }
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
      await roomsFeedModel.refresh(silentErrors: silentErrors);
      logFrontendDiagnostic(
        'rooms_refresh_completed',
        'Finished refreshing room summaries.',
        details: {
          'silent_errors': silentErrors,
          'room_count': roomsFeedModel.rooms.length,
          'room_ids': roomsFeedModel.rooms
              .take(10)
              .map((room) => room.id)
              .toList(),
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
      if (!roomsFeedModel.hasCachedData) {
        _showRefreshFailure('Could not refresh rooms. Trying again soon.');
      }
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
    for (final candidate in roomsFeedModel.rooms) {
      if (candidate.id == roomId) {
        room = candidate;
        break;
      }
    }
    if (room == null) {
      if (!roomsFeedModel.isLoadingInitial && !_reportedMissingInitialRoom) {
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
        settings: RouteSettings(name: roomsRouteWithOpenRoom(room.id)),
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
    final providedRoomsFeedModel = Provider.of<RoomsFeedModel?>(
      context,
      listen: false,
    );
    roomsFeedModel =
        widget.roomsFeedModel ??
        providedRoomsFeedModel ??
        RoomsFeedModel(httpService: httpService);
    _ownsRoomsFeedModel =
        widget.roomsFeedModel == null && providedRoomsFeedModel == null;
    final meModel = Provider.of<MeModel>(context, listen: false);
    _meModel = meModel;
    _meModel?.addListener(_handleSessionChanged);
    _syncFeedSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_ensureWarmRooms());
    });
    unawaited(websocketService.ensureConnected());
    if (widget.enableRealtimeRoomSummarySync) {
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final meModel = Provider.of<MeModel>(context);
    if (!identical(_meModel, meModel)) {
      _meModel?.removeListener(_handleSessionChanged);
      _meModel = meModel;
      _meModel?.addListener(_handleSessionChanged);
      _syncFeedSession();
    }
  }

  @override
  void dispose() {
    roomsChangedSubscription?.cancel();
    connectionEventsSubscription?.cancel();
    _meModel?.removeListener(_handleSessionChanged);
    if (_ownsRoomsFeedModel) {
      roomsFeedModel.dispose();
    }
    super.dispose();
  }

  void _handleSessionChanged() {
    _syncFeedSession();
  }

  void _syncFeedSession() {
    roomsFeedModel.syncSession(_meModel?.data);
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: roomsFeedModel,
      builder: (context, child) {
        final rooms = roomsFeedModel.rooms;
        final loadingInitialRooms = roomsFeedModel.isLoadingInitial;
        final roomsErrorMessage = roomsFeedModel.errorMessage;
        return Consumer<MeModel>(
          builder: (context, meModel, child) {
            final currentUser = meModel.data;
            final displayUser =
                currentUser ?? const SessionUser(authenticated: false);
            return ListView(
              children: [
                if (loadingInitialRooms)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (roomsErrorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Could not load rooms',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(roomsErrorMessage),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () {
                                unawaited(updateRooms());
                              },
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                              'Create a room with the button below, or browse nearby rooms to request access.',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: widget.onCreateRoom,
                                  child: const Text('Create room'),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      widget.onOpenNearby ??
                                      () {
                                        Navigator.pushReplacementNamed(
                                          context,
                                          '/nearby',
                                        );
                                      },
                                  child: const Text('Browse nearby'),
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
                        picture: room.displayPictureFor(displayUser),
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
                      title: Text(room.displayTitleFor(displayUser)),
                      subtitle: Text(_lastMessagePreview(room, currentUser)),
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
