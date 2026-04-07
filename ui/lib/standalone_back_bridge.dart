import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_route_state.dart';
import 'install_prompt_service.dart';
import 'me_model.dart';
import 'route_utils.dart';
import 'standalone_back_handler.dart';

class StandaloneBackBridge extends StatefulWidget {
  const StandaloneBackBridge({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.routeState,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final AppRouteState routeState;

  @override
  State<StandaloneBackBridge> createState() => _StandaloneBackBridgeState();
}

class _StandaloneBackBridgeState extends State<StandaloneBackBridge> {
  late final StandaloneBackHandler _handler;
  InstallPromptService? _installPromptService;

  @override
  void initState() {
    super.initState();
    _handler = createStandaloneBackHandler(onBackRequested: _handleBack);
    widget.routeState.addListener(_handleRouteStateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final installPromptService = Provider.of<InstallPromptService>(context);
    if (!identical(_installPromptService, installPromptService)) {
      _installPromptService?.removeListener(_handleInstallStateChanged);
      _installPromptService = installPromptService;
      _installPromptService?.addListener(_handleInstallStateChanged);
    }
    _syncStandaloneBackRoute(force: true);
  }

  @override
  void dispose() {
    widget.routeState.removeListener(_handleRouteStateChanged);
    _installPromptService?.removeListener(_handleInstallStateChanged);
    _handler.dispose();
    super.dispose();
  }

  void _handleInstallStateChanged() {
    _syncStandaloneBackRoute(force: true);
  }

  void _handleRouteStateChanged() {
    _syncStandaloneBackRoute();
  }

  Future<void> _handleBack() async {
    final navigator = widget.navigatorKey.currentState;
    final currentRouteName = widget.routeState.routeName;
    if (navigator == null || currentRouteName == null) {
      return;
    }
    final fallbackRoute = standaloneBackFallbackRoute(
      currentRouteName: currentRouteName,
      previousRouteName: widget.routeState.previousRouteName,
      me: Provider.of<MeModel?>(context, listen: false)?.data,
    );
    if (fallbackRoute == currentRouteName) {
      _syncStandaloneBackRoute(force: true);
      return;
    }
    navigator.pushReplacementNamed(fallbackRoute);
  }

  void _syncStandaloneBackRoute({bool force = false}) {
    final currentRouteName = widget.routeState.routeName;
    final installPromptService = _installPromptService;
    if (currentRouteName == null || installPromptService == null) {
      return;
    }
    _handler.updateRoute(
      enabled: installPromptService.isInstalled,
      route: currentRouteName,
      force: force,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
