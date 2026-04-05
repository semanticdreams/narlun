import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'me_model.dart';
import 'nearby_feed_model.dart';
import 'rooms_feed_model.dart';

class FeedSessionBridge extends StatefulWidget {
  const FeedSessionBridge({super.key, required this.child});

  final Widget child;

  @override
  State<FeedSessionBridge> createState() => _FeedSessionBridgeState();
}

class _FeedSessionBridgeState extends State<FeedSessionBridge> {
  MeModel? _meModel;
  NearbyFeedModel? _nearbyFeedModel;
  RoomsFeedModel? _roomsFeedModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final meModel = Provider.of<MeModel>(context);
    final nearbyFeedModel = Provider.of<NearbyFeedModel>(
      context,
      listen: false,
    );
    final roomsFeedModel = Provider.of<RoomsFeedModel>(context, listen: false);
    if (!identical(_meModel, meModel) ||
        !identical(_nearbyFeedModel, nearbyFeedModel) ||
        !identical(_roomsFeedModel, roomsFeedModel)) {
      _meModel?.removeListener(_handleSessionChanged);
      _meModel = meModel;
      _nearbyFeedModel = nearbyFeedModel;
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
    _nearbyFeedModel?.syncSession(session);
    _roomsFeedModel?.syncSession(session);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
