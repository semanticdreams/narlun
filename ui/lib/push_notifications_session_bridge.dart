import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'me_model.dart';
import 'push_notifications_service.dart';

class PushNotificationsSessionBridge extends StatefulWidget {
  const PushNotificationsSessionBridge({super.key, required this.child});

  final Widget child;

  @override
  State<PushNotificationsSessionBridge> createState() =>
      _PushNotificationsSessionBridgeState();
}

class _PushNotificationsSessionBridgeState
    extends State<PushNotificationsSessionBridge> {
  MeModel? _meModel;
  PushNotificationsService? _pushNotificationsService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final meModel = Provider.of<MeModel>(context);
    final pushNotificationsService =
        Provider.of<PushNotificationsService>(context, listen: false);
    if (!identical(_meModel, meModel) ||
        !identical(_pushNotificationsService, pushNotificationsService)) {
      _meModel?.removeListener(_handleSessionChanged);
      _meModel = meModel;
      _pushNotificationsService = pushNotificationsService;
      _meModel?.addListener(_handleSessionChanged);
      unawaited(_pushNotificationsService?.syncSession(_meModel?.data));
    }
  }

  @override
  void dispose() {
    _meModel?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    unawaited(_pushNotificationsService?.syncSession(_meModel?.data));
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
