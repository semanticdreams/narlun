import 'dart:async';

import 'standalone_back_handler_default.dart'
    if (dart.library.html) 'standalone_back_handler_browser.dart'
    as impl;

abstract class StandaloneBackHandler {
  void updateRoute({
    required bool enabled,
    required String route,
    bool force = false,
  });

  void dispose();
}

StandaloneBackHandler createStandaloneBackHandler({
  required FutureOr<void> Function() onBackRequested,
}) {
  return impl.createStandaloneBackHandler(onBackRequested: onBackRequested);
}
