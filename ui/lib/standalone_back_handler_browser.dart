// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'standalone_back_handler.dart';

const _standaloneBackStateKindKey = 'narlun_standalone_back_kind';
const _standaloneBackStateRouteKind = 'route';
const _standaloneBackStateGuardKind = 'guard';

class _BrowserStandaloneBackHandler implements StandaloneBackHandler {
  _BrowserStandaloneBackHandler({required this.onBackRequested}) {
    _popStateSubscription = html.window.onPopState.listen(_handlePopState);
  }

  final FutureOr<void> Function() onBackRequested;
  StreamSubscription<html.PopStateEvent>? _popStateSubscription;
  bool _enabled = false;
  bool _handlingBackRequest = false;
  String? _route;

  @override
  void updateRoute({
    required bool enabled,
    required String route,
    bool force = false,
  }) {
    _enabled = enabled;
    if (!_enabled) {
      return;
    }
    if (!force && _route == route) {
      return;
    }
    _route = route;
    _syncHistoryGuard();
  }

  void _syncHistoryGuard() {
    final route = _route;
    if (!_enabled || route == null || route.isEmpty) {
      return;
    }
    // Keep a guard entry ahead of the live route so standalone back gestures
    // land on an in-app history state that we can translate into app navigation.
    html.window.history.replaceState(
      <String, Object?>{
        _standaloneBackStateKindKey: _standaloneBackStateRouteKind,
        'route': route,
      },
      '',
      route,
    );
    html.window.history.pushState(
      <String, Object?>{
        _standaloneBackStateKindKey: _standaloneBackStateGuardKind,
        'route': route,
      },
      '',
      route,
    );
  }

  Map<Object?, Object?>? _eventStateFor(html.PopStateEvent event) {
    final raw = event.state;
    if (raw == null) {
      return null;
    }
    final value = js_util.dartify(raw);
    if (value is Map<Object?, Object?>) {
      return value;
    }
    return null;
  }

  void _handlePopState(html.PopStateEvent event) {
    if (!_enabled || _handlingBackRequest) {
      return;
    }
    final state = _eventStateFor(event);
    if (state == null ||
        state[_standaloneBackStateKindKey] != _standaloneBackStateRouteKind) {
      return;
    }
    _handlingBackRequest = true;
    Future<void>.microtask(() async {
      try {
        await onBackRequested();
      } finally {
        _handlingBackRequest = false;
      }
    });
  }

  @override
  void dispose() {
    _popStateSubscription?.cancel();
  }
}

StandaloneBackHandler createStandaloneBackHandler({
  required FutureOr<void> Function() onBackRequested,
}) {
  return _BrowserStandaloneBackHandler(onBackRequested: onBackRequested);
}
