// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'browser_notification_api.dart';

Future<String?> readCurrentPushSubscriptionEndpoint() async {
  final container = html.window.navigator.serviceWorker;
  if (container == null || !browserNotificationSupported()) {
    return null;
  }

  final registration = await container.ready;
  final pushManager = js_util.getProperty<Object>(registration, 'pushManager');
  final subscription = await js_util.promiseToFuture<Object?>(
    js_util.callMethod(pushManager, 'getSubscription', const []),
  );
  if (subscription == null) {
    return null;
  }
  final jsValue = js_util.callMethod<Object?>(subscription, 'toJSON', const []);
  final payload =
      jsonDecode(jsonEncode(js_util.dartify(jsValue))) as Map<String, dynamic>;
  final endpoint = payload['endpoint'];
  return endpoint is String && endpoint.isNotEmpty ? endpoint : null;
}
