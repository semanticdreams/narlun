// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js_util' as js_util;

bool detectInstalledWebApp() {
  final bootstrapInstalled =
      js_util.getProperty<Object?>(
            html.window,
            '__narlunInstalledFromBootstrap',
          ) !=
          null &&
      js_util.callMethod<bool>(
        html.window,
        '__narlunInstalledFromBootstrap',
        const [],
      );
  return isStandaloneWebAppContext() || bootstrapInstalled;
}

bool isStandaloneWebAppContext() {
  final standaloneMediaQuery = html.window.matchMedia(
    '(display-mode: standalone)',
  );
  final navigatorStandalone =
      js_util.getProperty<bool?>(html.window.navigator, 'standalone') == true;
  return standaloneMediaQuery.matches || navigatorStandalone;
}
