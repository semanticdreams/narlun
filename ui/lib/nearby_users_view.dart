import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'avatar_stack.dart';
import 'avatar_image.dart';
import 'dialog_service.dart';
import 'http.dart';
import 'location_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'session_actions.dart';
import 'websocket.dart';

class NearbyUsersView extends StatefulWidget {
  final FutureOr<void> Function(NearbyUser user, int roomId) onUserJoined;
  final HttpService? httpService;
  final DialogService? dialogService;
  final LocationService? locationService;
  final WebsocketService? websocketService;
  final bool autoCheckin;

  const NearbyUsersView({
    super.key,
    required this.onUserJoined,
    this.httpService,
    this.dialogService,
    this.locationService,
    this.websocketService,
    this.autoCheckin = true,
  });

  @override
  State<NearbyUsersView> createState() => _NearbyUsersState();
}

class _NearbyUsersState extends State<NearbyUsersView> {
  late final HttpService httpService;
  late final DialogService dialogService;
  late final LocationService locationService;
  late final WebsocketService websocketService;

  final List<NearbyItem> nearbyItems = [];
  bool _loading = false;
  String _statusMessage = 'Checking your location...';
  bool _didInitialCheckin = false;
  StreamSubscription? _nearbyChangedSubscription;
  StreamSubscription? _roomsChangedSubscription;
  StreamSubscription? _connectionEventsSubscription;

  @override
  void initState() {
    super.initState();
    httpService =
        widget.httpService ?? Provider.of<HttpService>(context, listen: false);
    dialogService = widget.dialogService ?? locator<DialogService>();
    locationService = widget.locationService ?? GeolocatorLocationService();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    _maybeStartInitialCheckin();
    unawaited(websocketService.ensureConnected());
    _nearbyChangedSubscription = websocketService.nearbyChangedStream().listen((_) {
      _refreshIfActive();
    });
    _roomsChangedSubscription = websocketService.roomsChangedStream().listen((_) {
      _refreshIfActive();
    });
    _connectionEventsSubscription = websocketService.connectionEvents.listen((event) {
      if (event == 'reconnected') {
        _refreshIfActive();
      }
    });
  }

  @override
  void didUpdateWidget(covariant NearbyUsersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadInitialCheckin = _didInitialCheckin;
    _maybeStartInitialCheckin();
    if (!oldWidget.autoCheckin && widget.autoCheckin && hadInitialCheckin) {
      unawaited(checkin());
    }
  }

  void _maybeStartInitialCheckin() {
    if (!widget.autoCheckin || _didInitialCheckin) {
      return;
    }
    _didInitialCheckin = true;
    unawaited(checkin());
  }

  void _refreshIfActive() {
    if (!widget.autoCheckin || !mounted) {
      return;
    }
    unawaited(checkin());
  }

  void _setStatus(String status, {required bool loading}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = loading;
      _statusMessage = status;
    });
  }

  Future<void> _showLocationProblem(String description) async {
    _setStatus(description, loading: false);
    await dialogService.showDialog(
      title: 'Location needed',
      description: description,
    );
  }

  Future<void> checkin() async {
    final me = Provider.of<MeModel>(context, listen: false);
    if (me.data == null || !me.data!.authenticated) {
      return;
    }
    _setStatus('Checking your location...', loading: true);

    if (!(await locationService.isLocationServiceEnabled())) {
      nearbyItems.clear();
      await _showLocationProblem('Location services are not enabled.');
      return;
    }

    var permission = await locationService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await locationService.requestPermission();
      if (permission == LocationPermission.denied) {
        nearbyItems.clear();
        await _showLocationProblem('Location access was denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      nearbyItems.clear();
      await _showLocationProblem(
        'Location access is permanently denied in this browser.',
      );
      return;
    }

    try {
      final loc = await locationService.getCurrentPosition();
      final resp = await httpService.checkin(loc.latitude, loc.longitude);
      if (!mounted) {
        return;
      }
      setState(() {
        nearbyItems
          ..clear()
          ..addAll(resp);
        _loading = false;
        _statusMessage = nearbyItems.isEmpty
            ? 'Nobody nearby right now. Pull to refresh again soon.'
            : 'Tap people to open a room, or rooms to request access.';
      });
    } on UnauthorizedResponse {
      if (!mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } catch (_) {
      nearbyItems.clear();
      _setStatus(
        'Could not refresh nearby activity. Pull to try again.',
        loading: false,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not refresh nearby activity.')),
      );
    }
  }

  Future<void> joinUser(NearbyUser user) async {
    final roomId = await httpService.join_user(user.id);
    await Future.sync(() => widget.onUserJoined(user, roomId));
  }

  Future<void> requestRoomJoin(NearbyRoom room) async {
    if (room.joinRequested) {
      return;
    }
    try {
      await httpService.request_room_join(room.room.id);
      if (!mounted) {
        return;
      }
      setState(() {
        for (var i = 0; i < nearbyItems.length; i++) {
          final candidate = nearbyItems[i];
          if (candidate.type == 'room' && candidate.room?.room.id == room.room.id) {
            nearbyItems[i] = NearbyItem(
              type: 'room',
              distance: candidate.distance,
              room: candidate.room?.copyWith(joinRequested: true),
            );
          }
        }
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Join request sent.')),
      );
    } on UnauthorizedResponse {
      if (!mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not send the join request.')),
      );
    }
  }

  @override
  void dispose() {
    _nearbyChangedSubscription?.cancel();
    _roomsChangedSubscription?.cancel();
    _connectionEventsSubscription?.cancel();
    super.dispose();
  }

  Widget _buildUserTile(NearbyUser user) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        key: ValueKey('nearby-user-${user.id}'),
        leading: AvatarImage(picture: user.picture),
        title: Text(user.username),
        subtitle: (user.status?.isNotEmpty ?? false)
            ? Text(
                user.status!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${user.distance}m away',
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 4),
            Text(
              'last seen ${timeago.format(user.lastSeen)}',
              textAlign: TextAlign.right,
            ),
          ],
        ),
        onTap: () async {
          await joinUser(user);
        },
      ),
    );
  }

  Widget _buildRoomTile(NearbyRoom room) {
    final previewPictures = room.room.participants
        .map((participant) => participant.picture)
        .toList();
    final distanceLabel = room.distance == null
        ? 'Waiting'
        : '${room.distance}m away';
    final subtitleLines = <Widget>[];
    if ((room.room.lastMessage?.body.isNotEmpty ?? false)) {
      subtitleLines.add(
        Text(
          room.room.lastMessage!.body,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
      subtitleLines.add(const SizedBox(height: 2));
    }
    subtitleLines.add(
      Text(
        '${room.room.memberCount} people',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        key: ValueKey('nearby-room-${room.room.id}'),
        leading: AvatarStack(
          pictures: previewPictures,
          totalCount: room.room.memberCount,
        ),
        title: Row(
          children: [
            const Icon(Icons.groups_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                room.room.name ?? 'Room with ${room.room.memberCount} people',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: subtitleLines,
        ),
        trailing: room.joinRequested
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Requested'),
              )
            : Text(distanceLabel, textAlign: TextAlign.right),
        onTap: room.joinRequested
            ? null
            : () async {
                await requestRoomJoin(room);
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: checkin,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
          ),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    if (_loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_loading) const SizedBox(width: 12),
                    Expanded(child: Text(_statusMessage)),
                  ],
                ),
              ),
              for (final item in nearbyItems)
                if (item.type == 'user' && item.user != null)
                  _buildUserTile(item.user!)
                else if (item.type == 'room' && item.room != null)
                  _buildRoomTile(item.room!),
            ],
          ),
        ),
      ),
    );
  }
}
