// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js_util' as js_util;

Object? _notificationConstructor() {
  try {
    if (!js_util.hasProperty(html.window, 'Notification')) {
      return null;
    }
    return js_util.getProperty<Object?>(html.window, 'Notification');
  } catch (_) {
    return null;
  }
}

bool browserNotificationSupported() {
  final notification = _notificationConstructor();
  if (notification == null) {
    return false;
  }
  try {
    return js_util.hasProperty(notification, 'permission') &&
        js_util.hasProperty(notification, 'requestPermission');
  } catch (_) {
    return false;
  }
}

String? browserNotificationPermission() {
  final notification = _notificationConstructor();
  if (notification == null) {
    return null;
  }
  try {
    final permission = js_util.getProperty<Object?>(notification, 'permission');
    return permission is String ? permission : null;
  } catch (_) {
    return null;
  }
}

Future<void> requestBrowserNotificationPermission() async {
  final notification = _notificationConstructor();
  if (notification == null) {
    return;
  }

  final result = js_util.callMethod<Object?>(
    notification,
    'requestPermission',
    const [],
  );
  if (result == null || result is String) {
    return;
  }
  if (!js_util.hasProperty(result, 'then')) {
    return;
  }
  await js_util.promiseToFuture<Object?>(result);
}
