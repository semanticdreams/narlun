import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'locator.dart';
import 'me_model.dart';
import 'websocket.dart';

class SessionWatcher extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const SessionWatcher({
    Key? key,
    required this.child,
    required this.navigatorKey,
  }) : super(key: key);

  @override
  State<SessionWatcher> createState() => _SessionWatcherState();
}

class _SessionWatcherState extends State<SessionWatcher> {
  late final WebsocketService websocketService;
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    websocketService = locator<WebsocketService>();
    _subscription = websocketService.connectionEvents.listen((event) {
      if (event == 'signed-out') {
        _handleSignedOut();
      }
    });
  }

  void _handleSignedOut() {
    if (!mounted) {
      return;
    }
    Provider.of<MeModel>(context, listen: false).reset();
    widget.navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
