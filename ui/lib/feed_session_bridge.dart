import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'invite_qr_cache.dart';
import 'me_model.dart';
import 'nearby_feed_model.dart';
import 'room_messages_cache.dart';
import 'rooms_feed_model.dart';

class FeedSessionBridge extends StatefulWidget {
  const FeedSessionBridge({super.key, required this.child});

  final Widget child;

  @override
  State<FeedSessionBridge> createState() => _FeedSessionBridgeState();
}

class _FeedSessionBridgeState extends State<FeedSessionBridge> {
  MeModel? _meModel;
  InviteQrCache? _inviteQrCache;
  NearbyFeedModel? _nearbyFeedModel;
  RoomMessagesCache? _roomMessagesCache;
  RoomsFeedModel? _roomsFeedModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final meModel = Provider.of<MeModel>(context);
    final inviteQrCache = Provider.of<InviteQrCache>(context, listen: false);
    final nearbyFeedModel = Provider.of<NearbyFeedModel>(
      context,
      listen: false,
    );
    final roomMessagesCache = Provider.of<RoomMessagesCache>(
      context,
      listen: false,
    );
    final roomsFeedModel = Provider.of<RoomsFeedModel>(context, listen: false);
    if (!identical(_meModel, meModel) ||
        !identical(_inviteQrCache, inviteQrCache) ||
        !identical(_nearbyFeedModel, nearbyFeedModel) ||
        !identical(_roomMessagesCache, roomMessagesCache) ||
        !identical(_roomsFeedModel, roomsFeedModel)) {
      _meModel?.removeListener(_handleSessionChanged);
      _meModel = meModel;
      _inviteQrCache = inviteQrCache;
      _nearbyFeedModel = nearbyFeedModel;
      _roomMessagesCache = roomMessagesCache;
      _roomsFeedModel = roomsFeedModel;
      _meModel?.addListener(_handleSessionChanged);
      _syncModels();
    }
  }

  @override
  void dispose() {
    _meModel?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    _syncModels();
  }

  void _syncModels() {
    final session = _meModel?.data;
    _inviteQrCache?.syncSession(session);
    _nearbyFeedModel?.syncSession(session);
    _roomMessagesCache?.syncSession(session);
    _roomsFeedModel?.syncSession(session);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
