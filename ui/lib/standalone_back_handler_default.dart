import 'dart:async';

import 'standalone_back_handler.dart';

class _DefaultStandaloneBackHandler implements StandaloneBackHandler {
  @override
  void updateRoute({
    required bool enabled,
    required String route,
    bool force = false,
  }) {}

  @override
  void dispose() {}
}

StandaloneBackHandler createStandaloneBackHandler({
  required FutureOr<void> Function() onBackRequested,
}) {
  return _DefaultStandaloneBackHandler();
}
