import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

Future<String?> readCurrentPushSubscriptionEndpoint() async {
  final container = html.window.navigator.serviceWorker;
  if (container == null || !html.Notification.supported) {
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
