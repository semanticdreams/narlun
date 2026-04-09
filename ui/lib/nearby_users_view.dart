import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_stack.dart';
import 'dialog_service.dart';
import 'frontend_error_reporter.dart';
import 'http.dart';
import 'location_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'nearby_feed_model.dart';
import 'session_actions.dart';
import 'websocket.dart';

class NearbyUsersView extends StatefulWidget {
  static const defaultBackgroundRefreshInterval =
      NearbyFeedModel.minAutomaticRefreshInterval;

  final HttpService? httpService;
  final DialogService? dialogService;
  final LocationService? locationService;
  final WebsocketService? websocketService;
  final NearbyFeedModel? nearbyFeedModel;
  final bool autoCheckin;
  final Duration backgroundRefreshInterval;

  const NearbyUsersView({
    super.key,
    this.httpService,
    this.dialogService,
    this.locationService,
    this.websocketService,
    this.nearbyFeedModel,
    this.autoCheckin = true,
    this.backgroundRefreshInterval = defaultBackgroundRefreshInterval,
  });

  @override
  State<NearbyUsersView> createState() => _NearbyUsersState();
}

class _NearbyUsersState extends State<NearbyUsersView> {
  MeModel? _meModel;
  late final HttpService httpService;
  late final DialogService dialogService;
  late final WebsocketService websocketService;
  late final NearbyFeedModel nearbyFeedModel;
  bool _ownsNearbyFeedModel = false;
  StreamSubscription? _nearbyChangedSubscription;
  StreamSubscription? _connectionEventsSubscription;
  Timer? _backgroundRefreshTimer;

  @override
  void initState() {
    super.initState();
    httpService =
        widget.httpService ?? Provider.of<HttpService>(context, listen: false);
    dialogService = widget.dialogService ?? locator<DialogService>();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    final providedNearbyFeedModel = Provider.of<NearbyFeedModel?>(
      context,
      listen: false,
    );
    nearbyFeedModel =
        widget.nearbyFeedModel ??
        providedNearbyFeedModel ??
        NearbyFeedModel(
          httpService: httpService,
          locationService: widget.locationService ?? createLocationService(),
        );
    _ownsNearbyFeedModel =
        widget.nearbyFeedModel == null && providedNearbyFeedModel == null;
    final meModel = Provider.of<MeModel>(context, listen: false);
    _meModel = meModel;
    _meModel?.addListener(_handleSessionChanged);
    _syncFeedSession();
    _maybeStartInitialCheckin();
    _syncBackgroundRefreshTimer();
    unawaited(websocketService.ensureConnected());
    _nearbyChangedSubscription = websocketService.nearbyChangedStream().listen((
      _,
    ) {
      _refreshIfActive();
    });
    _connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) {
      if (event == 'reconnected') {
        _refreshIfActive();
      }
    });
  }

  @override
  void didUpdateWidget(covariant NearbyUsersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoCheckin != widget.autoCheckin ||
        oldWidget.backgroundRefreshInterval !=
            widget.backgroundRefreshInterval) {
      _syncBackgroundRefreshTimer();
    }
    if (!oldWidget.autoCheckin && widget.autoCheckin) {
      unawaited(_ensureWarmNearby());
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

  void _maybeStartInitialCheckin() {
    if (!widget.autoCheckin) {
      return;
    }
    unawaited(_ensureWarmNearby());
  }

  void _refreshIfActive() {
    if (!widget.autoCheckin || !mounted) {
      return;
    }
    unawaited(checkin(showErrorFeedback: false, userInitiated: false));
  }

  void _handleSessionChanged() {
    _syncFeedSession();
  }

  void _syncBackgroundRefreshTimer() {
    _backgroundRefreshTimer?.cancel();
    if (!widget.autoCheckin) {
      return;
    }
    _backgroundRefreshTimer = Timer.periodic(
      widget.backgroundRefreshInterval,
      (_) => _refreshIfActive(),
    );
  }

  void _syncFeedSession() {
    nearbyFeedModel.syncSession(_meModel?.data);
  }

  Future<void> _showLocationProblem(String description) async {
    logFrontendDiagnostic(
      'nearby_location_problem',
      'Nearby check-in could not continue because location is unavailable.',
      details: {'description': description},
    );
    await dialogService.showDialog(
      title: 'Location needed',
      description: description,
    );
  }

  Future<void> _ensureWarmNearby() async {
    try {
      await nearbyFeedModel.ensureWarm();
    } on UnauthorizedResponse {
      if (!mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } on NearbyLocationProblem {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> checkin({
    bool showErrorFeedback = true,
    bool userInitiated = true,
  }) async {
    final me = Provider.of<MeModel>(context, listen: false);
    if (me.data == null || !me.data!.authenticated) {
      return;
    }
    logFrontendDiagnostic(
      'nearby_checkin_started',
      'Started nearby check-in.',
      details: {
        'show_error_feedback': showErrorFeedback,
        'user_initiated': userInitiated,
        'user_id': me.data?.id,
      },
    );

    try {
      await nearbyFeedModel.refresh(userInitiated: userInitiated);
      logFrontendDiagnostic(
        'nearby_checkin_completed',
        'Completed nearby check-in.',
        details: {'result_count': nearbyFeedModel.nearbyItems.length},
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
    } on NearbyLocationProblem catch (problem) {
      if (!showErrorFeedback) {
        return;
      }
      await _showLocationProblem(problem.description);
    } catch (error) {
      logFrontendDiagnostic(
        'nearby_checkin_failed',
        'Nearby check-in failed.',
        details: {
          'error': error.toString(),
          'show_error_feedback': showErrorFeedback,
        },
      );
      if (!showErrorFeedback) {
        return;
      }
      if (!mounted) {
        return;
      }
      if (isAlreadyPresentedActionError(error)) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            describeActionError(
              error,
              fallbackDescription:
                  'Could not refresh nearby activity. Try again later.',
            ),
          ),
        ),
      );
    }
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
      nearbyFeedModel.markRoomJoinRequested(room.room.id);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Join request sent.')));
    } on UnauthorizedResponse {
      if (!mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (isAlreadyPresentedActionError(error)) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            describeActionError(
              error,
              fallbackDescription: 'Could not send the join request.',
            ),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _backgroundRefreshTimer?.cancel();
    _nearbyChangedSubscription?.cancel();
    _connectionEventsSubscription?.cancel();
    _meModel?.removeListener(_handleSessionChanged);
    if (_ownsNearbyFeedModel) {
      nearbyFeedModel.dispose();
    }
    super.dispose();
  }

  Widget _buildRoomTile(NearbyRoom room) {
    final previewPictures = room.room.participants
        .map((participant) => participant.picture)
        .toList();
    final distanceLabel = room.distance == null
        ? 'Waiting'
        : '${room.distance}m away';
    final subtitleLines = <Widget>[];
    if ((room.room.lastMessage?.previewText.isNotEmpty ?? false)) {
      subtitleLines.add(
        Text(
          room.room.lastMessage!.previewText,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
    return ListenableBuilder(
      listenable: nearbyFeedModel,
      builder: (context, child) {
        final nearbyItems = nearbyFeedModel.nearbyItems;
        final loading = nearbyFeedModel.loading;
        final statusMessage = nearbyFeedModel.statusMessage;
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
                        if (loading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (loading) const SizedBox(width: 12),
                        Expanded(child: Text(statusMessage)),
                      ],
                    ),
                  ),
                  for (final item in nearbyItems)
                    if (item.type == 'room' && item.room != null)
                      _buildRoomTile(item.room!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
