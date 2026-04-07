import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'locator.dart';
import 'me_model.dart';
import 'rooms_feed_model.dart';
import 'websocket.dart';

class RoomsFeedRefreshBridge extends StatefulWidget {
  const RoomsFeedRefreshBridge({super.key, required this.child});

  final Widget child;

  @override
  State<RoomsFeedRefreshBridge> createState() => _RoomsFeedRefreshBridgeState();
}

class _RoomsFeedRefreshBridgeState extends State<RoomsFeedRefreshBridge> {
  MeModel? _meModel;
  RoomsFeedModel? _roomsFeedModel;
  WebsocketService? _websocketService;
  StreamSubscription<Map<String, dynamic>>? _roomsChangedSubscription;
  StreamSubscription<String>? _connectionEventsSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final meModel = Provider.of<MeModel>(context);
    final roomsFeedModel = Provider.of<RoomsFeedModel>(context, listen: false);
    final websocketService = locator<WebsocketService>();
    final bindingsChanged =
        !identical(_meModel, meModel) ||
        !identical(_roomsFeedModel, roomsFeedModel) ||
        !identical(_websocketService, websocketService);
    if (!bindingsChanged) {
      return;
    }
    _meModel = meModel;
    _roomsFeedModel = roomsFeedModel;
    _websocketService = websocketService;
    _roomsChangedSubscription?.cancel();
    _connectionEventsSubscription?.cancel();
    _roomsChangedSubscription = websocketService.roomsChangedStream().listen((
      _,
    ) {
      _refreshRoomsIfWarm();
    });
    _connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) {
      if (event == 'reconnected') {
        _refreshRoomsIfWarm();
      }
    });
  }

  @override
  void dispose() {
    _roomsChangedSubscription?.cancel();
    _connectionEventsSubscription?.cancel();
    super.dispose();
  }

  void _refreshRoomsIfWarm() {
    final me = _meModel?.data;
    final roomsFeedModel = _roomsFeedModel;
    if (me?.authenticated != true || roomsFeedModel == null) {
      return;
    }
    if (!roomsFeedModel.hasCachedData) {
      return;
    }
    unawaited(roomsFeedModel.refresh(silentErrors: true));
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
