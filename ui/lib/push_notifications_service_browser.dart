import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_client_browser.dart' as session_http;
import 'models.dart';
import 'push_notifications_service.dart';
import 'client_identity_default.dart'
    if (dart.library.html) 'client_identity_browser.dart' as client_identity;

const _pushPromptDismissedUntilKey =
    'narlun.pushPromptSuggestionDismissedUntil';

class BrowserPushNotificationsService extends PushNotificationsService {
  BrowserPushNotificationsService({required this.apiBaseUrl})
    : _client = session_http.createHttpClient() {
    _permissionState = _readPermissionState();
  }

  final String apiBaseUrl;
  final http.Client _client;

  bool _isConfigured = false;
  bool _isSubscribed = false;
  bool _isBusy = false;
  PushPermissionState _permissionState = PushPermissionState.unsupported;
  int? _currentUserId;
  String? _vapidPublicKey;
  bool _hasSyncedSession = false;

  @override
  bool get isSupported =>
      html.Notification.supported &&
      html.window.navigator.serviceWorker != null;

  @override
  bool get isConfigured => _isConfigured;

  @override
  bool get isSubscribed => _isSubscribed;

  @override
  bool get isBusy => _isBusy;

  @override
  bool get shouldShowPrompt {
    if (!isSupported || _currentUserId == null || !_isConfigured) {
      return false;
    }
    if (_isSubscribed || _permissionState == PushPermissionState.denied) {
      return false;
    }
    return !_isPromptDismissedForNow;
  }

  @override
  PushPermissionState get permissionState => _permissionState;

  @override
  String? get statusMessage {
    if (!isSupported) {
      return null;
    }
    if (_currentUserId == null) {
      return null;
    }
    if (!isConfigured) {
      return 'Notifications are not configured on this server yet.';
    }
    switch (_permissionState) {
      case PushPermissionState.defaultState:
        return _isSubscribed
            ? 'Notifications are enabled for this browser.'
            : 'Notifications are off for this browser.';
      case PushPermissionState.granted:
        return _isSubscribed
            ? 'Notifications are enabled for this browser.'
            : 'Notifications permission is granted, but this browser is not subscribed yet.';
      case PushPermissionState.denied:
        return 'Browser notifications are blocked for this site.';
      case PushPermissionState.unsupported:
        return null;
    }
  }

  @override
  Future<void> syncSession(SessionUser? user) async {
    _permissionState = _readPermissionState();
    final nextUserId =
        user?.authenticated == true && user?.id != null ? user!.id : null;
    if (_currentUserId == nextUserId && _hasSyncedSession) {
      notifyListeners();
      return;
    }

    _currentUserId = nextUserId;
    _hasSyncedSession = true;
    if (_currentUserId == null) {
      _isConfigured = false;
      _isSubscribed = false;
      _vapidPublicKey = null;
      notifyListeners();
      return;
    }

    await _refreshServerConfig();
    if (_isConfigured && _permissionState == PushPermissionState.granted) {
      await _syncCurrentSubscription(registerWithServer: true);
    } else {
      _isSubscribed = false;
      notifyListeners();
    }
  }

  @override
  Future<void> enableNotifications() async {
    if (!isSupported || _currentUserId == null) {
      return;
    }

    await _runBusy(() async {
      await _refreshServerConfig();
      if (!_isConfigured || _vapidPublicKey == null) {
        return;
      }

      if (html.Notification.permission != 'granted') {
        await html.Notification.requestPermission();
      }
      _permissionState = _readPermissionState();
      if (_permissionState != PushPermissionState.granted) {
        _isSubscribed = false;
        return;
      }

      final registration = await _getServiceWorkerRegistration();
      if (registration == null) {
        return;
      }

      final pushManager = js_util.getProperty<Object>(registration, 'pushManager');
      final options = js_util.newObject();
      js_util.setProperty(options, 'userVisibleOnly', true);
      js_util.setProperty(
        options,
        'applicationServerKey',
        _decodeVapidPublicKey(_vapidPublicKey!),
      );
      var subscription = await _getCurrentSubscription(pushManager);
      subscription ??= await js_util.promiseToFuture<Object?>(
        js_util.callMethod(pushManager, 'subscribe', [options]),
      );
      if (subscription == null) {
        return;
      }
      await _saveSubscription(subscription);
      _clearDismissedPrompt();
      _isSubscribed = true;
    });
  }

  @override
  Future<void> disableNotifications() async {
    if (!isSupported || _currentUserId == null) {
      return;
    }

    await _runBusy(() async {
      final registration = await _getServiceWorkerRegistration();
      if (registration == null) {
        _isSubscribed = false;
        return;
      }

      final pushManager = js_util.getProperty<Object>(registration, 'pushManager');
      final subscription = await _getCurrentSubscription(pushManager);
      if (subscription == null) {
        _isSubscribed = false;
        return;
      }

      final endpoint = _subscriptionJson(subscription)['endpoint'] as String?;
      if (endpoint != null && endpoint.isNotEmpty) {
        await _deleteSubscriptionFromServer(endpoint);
      }
      await js_util.promiseToFuture<bool>(
        js_util.callMethod(subscription, 'unsubscribe', const []),
      );
      _isSubscribed = false;
    });
  }

  @override
  void dismissPrompt() {
    final dismissedUntil = DateTime.now()
        .toUtc()
        .add(const Duration(days: 7))
        .toIso8601String();
    html.window.localStorage[_pushPromptDismissedUntilKey] = dismissedUntil;
    notifyListeners();
  }

  Future<void> _refreshServerConfig() async {
    final response = await _client.get(Uri.parse('$apiBaseUrl/users/push-config'));
    if (response.statusCode != 200) {
      _isConfigured = false;
      _vapidPublicKey = null;
      notifyListeners();
      return;
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    _isConfigured = body['enabled'] == true;
    _vapidPublicKey = body['vapid_public_key'] as String?;
    notifyListeners();
  }

  Future<void> _syncCurrentSubscription({required bool registerWithServer}) async {
    final registration = await _getServiceWorkerRegistration();
    if (registration == null) {
      _isSubscribed = false;
      notifyListeners();
      return;
    }

    final pushManager = js_util.getProperty<Object>(registration, 'pushManager');
    final subscription = await _getCurrentSubscription(pushManager);
    if (subscription == null) {
      _isSubscribed = false;
      notifyListeners();
      return;
    }

    if (registerWithServer) {
      await _saveSubscription(subscription);
    }
    _isSubscribed = true;
    notifyListeners();
  }

  Future<void> _saveSubscription(Object subscription) async {
    final clientId = await client_identity.readClientIdentity();
    final response = await _client.post(
      Uri.parse('$apiBaseUrl/users/push-subscriptions'),
      body: jsonEncode({
        'subscription': _subscriptionJson(subscription),
        'client_id': clientId,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      _isSubscribed = true;
      notifyListeners();
    }
  }

  Future<void> _deleteSubscriptionFromServer(String endpoint) async {
    await _client.delete(
      Uri.parse('$apiBaseUrl/users/push-subscriptions'),
      body: jsonEncode({'endpoint': endpoint}),
    );
  }

  Future<Object?> _getCurrentSubscription(Object pushManager) {
    return js_util.promiseToFuture<Object?>(
      js_util.callMethod(pushManager, 'getSubscription', const []),
    );
  }

  Future<html.ServiceWorkerRegistration?> _getServiceWorkerRegistration() async {
    final container = html.window.navigator.serviceWorker;
    if (container == null) {
      return null;
    }
    return container.ready;
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    _isBusy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _permissionState = _readPermissionState();
      _isBusy = false;
      notifyListeners();
    }
  }

  bool get _isPromptDismissedForNow {
    final value = html.window.localStorage[_pushPromptDismissedUntilKey];
    if (value == null) {
      return false;
    }
    final dismissedUntil = DateTime.tryParse(value);
    if (dismissedUntil == null) {
      _clearDismissedPrompt();
      return false;
    }
    if (dismissedUntil.isAfter(DateTime.now().toUtc())) {
      return true;
    }
    _clearDismissedPrompt();
    return false;
  }

  PushPermissionState _readPermissionState() {
    if (!isSupported) {
      return PushPermissionState.unsupported;
    }
    switch (html.Notification.permission) {
      case 'granted':
        return PushPermissionState.granted;
      case 'denied':
        return PushPermissionState.denied;
      default:
        return PushPermissionState.defaultState;
    }
  }

  void _clearDismissedPrompt() {
    html.window.localStorage.remove(_pushPromptDismissedUntilKey);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

Map<String, dynamic> _subscriptionJson(Object subscription) {
  final jsValue = js_util.callMethod<Object?>(subscription, 'toJSON', const []);
  return jsonDecode(jsonEncode(js_util.dartify(jsValue))) as Map<String, dynamic>;
}

Uint8List _decodeVapidPublicKey(String value) {
  final normalized = base64.normalize(
    value.replaceAll('-', '+').replaceAll('_', '/'),
  );
  return base64Decode(normalized);
}

PushNotificationsService createPushNotificationsService({String? apiBaseUrl}) {
  return BrowserPushNotificationsService(apiBaseUrl: apiBaseUrl ?? '/api');
}
