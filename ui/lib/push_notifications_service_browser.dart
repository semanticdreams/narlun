// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'frontend_error_reporter.dart';
import 'http_client_browser.dart' as session_http;
import 'models.dart';
import 'push_notifications_service.dart';
import 'client_identity_default.dart'
    if (dart.library.html) 'client_identity_browser.dart'
    as client_identity;

const _pushPromptDismissedUntilKey =
    'narlun.pushPromptSuggestionDismissedUntil';
const _serviceWorkerReadyTimeout = Duration(seconds: 10);

class BrowserPushNotificationsService extends PushNotificationsService {
  BrowserPushNotificationsService({required this.apiBaseUrl})
    : _client = session_http.createHttpClient() {
    _permissionState = _readPermissionState();
    _log(
      'service_initialized',
      'Initialized browser push notifications service.',
      details: _pushStateDetails(
        extra: {
          'is_supported': isSupported,
          'notification_permission': html.Notification.permission,
          'service_worker_supported':
              html.window.navigator.serviceWorker != null,
          'is_secure_context': html.window.isSecureContext == true,
          'service_worker_controller_present':
              html.window.navigator.serviceWorker != null &&
              js_util.getProperty<Object?>(
                    html.window.navigator.serviceWorker!,
                    'controller',
                  ) !=
                  null,
        },
      ),
    );
  }

  final String apiBaseUrl;
  final http.Client _client;

  bool _isConfigured = false;
  bool _isSubscribed = false;
  bool _isBusy = false;
  bool _hasBrowserSubscription = false;
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
            : _hasBrowserSubscription
            ? 'Notifications permission is granted, but this browser is not fully registered with the server yet.'
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
    final nextUserId = user?.authenticated == true && user?.id != null
        ? user!.id
        : null;
    if (_currentUserId == nextUserId && _hasSyncedSession) {
      _log(
        'session_sync_skipped',
        'Skipped push session sync because nothing changed.',
        details: _pushStateDetails(extra: {'user_id': _currentUserId}),
      );
      notifyListeners();
      return;
    }

    _currentUserId = nextUserId;
    _hasSyncedSession = true;
    if (_currentUserId == null) {
      _isConfigured = false;
      _isSubscribed = false;
      _hasBrowserSubscription = false;
      _vapidPublicKey = null;
      notifyListeners();
      _log('session_cleared', 'Cleared push session state.');
      return;
    }

    await _refreshServerConfig();
    if (_isConfigured && _permissionState == PushPermissionState.granted) {
      await _syncCurrentSubscription(registerWithServer: true);
    } else {
      _isSubscribed = false;
      _hasBrowserSubscription = false;
      notifyListeners();
    }
    _log(
      'session_synced',
      'Synchronized push session state.',
      details: {
        'user_id': _currentUserId,
        'is_configured': _isConfigured,
        'is_subscribed': _isSubscribed,
        'permission_state': _permissionState.name,
      },
    );
  }

  @override
  Future<void> enableNotifications() async {
    if (!isSupported || _currentUserId == null) {
      return;
    }

    await _runBusy(() async {
      await _refreshServerConfig();
      if (!_isConfigured || _vapidPublicKey == null) {
        _log(
          'enable_unavailable',
          'Push notifications are unavailable because the server is not configured.',
          details: _pushStateDetails(extra: {'user_id': _currentUserId}),
        );
        return;
      }

      if (html.Notification.permission != 'granted') {
        _log(
          'request_permission_started',
          'Requesting browser notification permission.',
          details: _pushStateDetails(
            extra: {'current_permission': html.Notification.permission},
          ),
        );
        await html.Notification.requestPermission();
      }
      _permissionState = _readPermissionState();
      _log(
        'request_permission_completed',
        'Completed browser notification permission request.',
        details: _pushStateDetails(
          extra: {'current_permission': html.Notification.permission},
        ),
      );
      if (_permissionState != PushPermissionState.granted) {
        _isSubscribed = false;
        _hasBrowserSubscription = false;
        _log(
          'request_permission_rejected',
          'Browser notification permission was not granted.',
          details: _pushStateDetails(
            extra: {'permission_state': _permissionState.name},
          ),
        );
        return;
      }

      final registration = await _getServiceWorkerRegistration();
      if (registration == null) {
        _isSubscribed = false;
        _hasBrowserSubscription = false;
        notifyListeners();
        _log(
          'registration_missing',
          'Browser service worker registration was unavailable for push subscription.',
        );
        return;
      }

      final pushManager = js_util.getProperty<Object>(
        registration,
        'pushManager',
      );
      final options = js_util.newObject();
      js_util.setProperty(options, 'userVisibleOnly', true);
      js_util.setProperty(
        options,
        'applicationServerKey',
        _decodeVapidPublicKey(_vapidPublicKey!),
      );
      var subscription = await _getCurrentSubscription(pushManager);
      _log(
        'existing_subscription_checked',
        'Checked for an existing browser push subscription.',
        details: _pushStateDetails(
          extra: {
            'has_existing_subscription': subscription != null,
            ..._registrationDetails(registration),
            ..._subscriptionDetails(subscription),
          },
        ),
      );
      if (subscription == null) {
        try {
          subscription = await js_util.promiseToFuture<Object?>(
            js_util.callMethod(pushManager, 'subscribe', [options]),
          );
        } catch (error) {
          _log(
            'subscribe_failed',
            'Browser push subscription request failed.',
            details: _pushStateDetails(
              extra: {
                'error': error.toString(),
                ..._registrationDetails(registration),
              },
            ),
          );
          rethrow;
        }
      }
      if (subscription == null) {
        _isSubscribed = false;
        _hasBrowserSubscription = false;
        notifyListeners();
        _log(
          'subscription_missing',
          'Browser push subscription was not created.',
          details: _pushStateDetails(extra: _registrationDetails(registration)),
        );
        return;
      }
      _hasBrowserSubscription = true;
      final savedToServer = await _saveSubscription(subscription);
      _isSubscribed = savedToServer;
      notifyListeners();
      if (!savedToServer) {
        return;
      }
      _clearDismissedPrompt();
      _log(
        'enable_completed',
        'Push notifications were enabled.',
        details: {'user_id': _currentUserId, 'is_subscribed': _isSubscribed},
      );
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
        _hasBrowserSubscription = false;
        _log(
          'disable_registration_missing',
          'No service worker registration was available while disabling push notifications.',
          details: _pushStateDetails(),
        );
        return;
      }

      final pushManager = js_util.getProperty<Object>(
        registration,
        'pushManager',
      );
      final subscription = await _getCurrentSubscription(pushManager);
      if (subscription == null) {
        _isSubscribed = false;
        _hasBrowserSubscription = false;
        _log(
          'disable_subscription_missing',
          'No browser push subscription was present while disabling push notifications.',
          details: _pushStateDetails(extra: _registrationDetails(registration)),
        );
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
      _hasBrowserSubscription = false;
      _log(
        'disable_completed',
        'Push notifications were disabled.',
        details: {'user_id': _currentUserId},
      );
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
    late final http.Response response;
    try {
      response = await _client.get(Uri.parse('$apiBaseUrl/users/push-config'));
    } catch (error) {
      _isConfigured = false;
      _vapidPublicKey = null;
      notifyListeners();
      _log(
        'config_request_failed',
        'Push configuration request failed.',
        details: _pushStateDetails(extra: {'error': error.toString()}),
      );
      return;
    }
    if (response.statusCode != 200) {
      _isConfigured = false;
      _vapidPublicKey = null;
      notifyListeners();
      _log(
        'config_request_failed',
        'Push configuration request failed.',
        details: _pushStateDetails(extra: {'status_code': response.statusCode}),
      );
      return;
    }
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _isConfigured = body['enabled'] == true;
      _vapidPublicKey = body['vapid_public_key'] as String?;
      notifyListeners();
      _log(
        'config_loaded',
        'Loaded push configuration from the server.',
        details: _pushStateDetails(
          extra: {
            'enabled': _isConfigured,
            'vapid_public_key_present':
                _vapidPublicKey != null && _vapidPublicKey!.isNotEmpty,
          },
        ),
      );
    } catch (error) {
      _isConfigured = false;
      _vapidPublicKey = null;
      notifyListeners();
      _log(
        'config_response_invalid',
        'Push configuration response could not be decoded.',
        details: _pushStateDetails(
          extra: {
            'status_code': response.statusCode,
            'error': error.toString(),
          },
        ),
      );
    }
  }

  Future<void> _syncCurrentSubscription({
    required bool registerWithServer,
  }) async {
    final registration = await _getServiceWorkerRegistration();
    if (registration == null) {
      _isSubscribed = false;
      _hasBrowserSubscription = false;
      notifyListeners();
      _log(
        'sync_registration_missing',
        'No browser service worker registration was available while syncing push subscription.',
        details: _pushStateDetails(),
      );
      return;
    }

    final pushManager = js_util.getProperty<Object>(
      registration,
      'pushManager',
    );
    final subscription = await _getCurrentSubscription(pushManager);
    if (subscription == null) {
      _isSubscribed = false;
      _hasBrowserSubscription = false;
      notifyListeners();
      _log(
        'sync_subscription_missing',
        'No browser push subscription exists for the current session.',
        details: _pushStateDetails(extra: _registrationDetails(registration)),
      );
      return;
    }

    _hasBrowserSubscription = true;
    if (registerWithServer) {
      _isSubscribed = await _saveSubscription(subscription);
    } else {
      _isSubscribed = true;
    }
    notifyListeners();
    _log(
      'sync_subscription_found',
      'Found an existing browser push subscription.',
      details: _pushStateDetails(
        extra: {
          'register_with_server': registerWithServer,
          ..._registrationDetails(registration),
          ..._subscriptionDetails(subscription),
        },
      ),
    );
  }

  Future<bool> _saveSubscription(Object subscription) async {
    final clientId = await client_identity.readClientIdentity();
    late final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$apiBaseUrl/users/push-subscriptions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'subscription': _subscriptionJson(subscription),
          'client_id': clientId,
        }),
      );
    } catch (error) {
      _log(
        'subscription_save_failed',
        'Could not send the browser push subscription to the server.',
        details: _pushStateDetails(
          extra: {
            'client_id': clientId,
            'error': error.toString(),
            ..._subscriptionDetails(subscription),
          },
        ),
      );
      return false;
    }
    if (response.statusCode == 200 || response.statusCode == 204) {
      _log(
        'subscription_saved',
        'Saved the browser push subscription on the server.',
        details: _pushStateDetails(
          extra: {
            'status_code': response.statusCode,
            'client_id': clientId,
            ..._subscriptionDetails(subscription),
          },
        ),
      );
      return true;
    }
    _log(
      'subscription_save_failed',
      'Server did not accept the browser push subscription.',
      details: _pushStateDetails(
        extra: {
          'status_code': response.statusCode,
          'client_id': clientId,
          ..._subscriptionDetails(subscription),
        },
      ),
    );
    return false;
  }

  Future<void> _deleteSubscriptionFromServer(String endpoint) async {
    try {
      final response = await _client.delete(
        Uri.parse('$apiBaseUrl/users/push-subscriptions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'endpoint': endpoint}),
      );
      _log(
        'subscription_deleted',
        'Asked the server to delete a browser push subscription.',
        details: _pushStateDetails(
          extra: {
            'status_code': response.statusCode,
            'endpoint_origin': _endpointOrigin(endpoint),
          },
        ),
      );
    } catch (error) {
      _log(
        'subscription_delete_failed',
        'Could not ask the server to delete the browser push subscription.',
        details: _pushStateDetails(
          extra: {
            'endpoint_origin': _endpointOrigin(endpoint),
            'error': error.toString(),
          },
        ),
      );
    }
  }

  Future<Object?> _getCurrentSubscription(Object pushManager) async {
    try {
      return await js_util.promiseToFuture<Object?>(
        js_util.callMethod(pushManager, 'getSubscription', const []),
      );
    } catch (error) {
      _log(
        'subscription_lookup_failed',
        'Browser push subscription lookup failed.',
        details: _pushStateDetails(extra: {'error': error.toString()}),
      );
      return null;
    }
  }

  Future<html.ServiceWorkerRegistration?>
  _getServiceWorkerRegistration() async {
    final container = html.window.navigator.serviceWorker;
    if (container == null) {
      _log(
        'registration_unavailable',
        'Browser does not expose service worker support.',
        details: _pushStateDetails(),
      );
      return null;
    }
    try {
      final registration = await container.ready.timeout(
        _serviceWorkerReadyTimeout,
      );
      _log(
        'registration_ready',
        'Browser service worker registration became ready.',
        details: _pushStateDetails(extra: _registrationDetails(registration)),
      );
      return registration;
    } on TimeoutException {
      _log(
        'registration_ready_timed_out',
        'Timed out waiting for the browser service worker registration.',
        details: _pushStateDetails(
          extra: {
            'timeout_ms': _serviceWorkerReadyTimeout.inMilliseconds,
            'service_worker_controller_present':
                js_util.getProperty<Object?>(container, 'controller') != null,
          },
        ),
      );
      return null;
    } catch (error) {
      _log(
        'registration_failed',
        'Browser service worker registration lookup failed.',
        details: _pushStateDetails(extra: {'error': error.toString()}),
      );
      return null;
    }
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

  void _log(String kind, String message, {Map<String, Object?>? details}) {
    logFrontendDiagnostic(
      'push_$kind',
      message,
      details: _pushStateDetails(extra: details),
    );
  }

  Map<String, Object?> _pushStateDetails({Map<String, Object?>? extra}) {
    return {
      'user_id': _currentUserId,
      'permission_state': _permissionState.name,
      'notification_permission': html.Notification.permission,
      'is_configured': _isConfigured,
      'is_subscribed': _isSubscribed,
      'has_browser_subscription': _hasBrowserSubscription,
      'is_busy': _isBusy,
      'should_show_prompt': shouldShowPrompt,
      'service_worker_supported': html.window.navigator.serviceWorker != null,
      ...?extra,
    };
  }

  Map<String, Object?> _registrationDetails(
    html.ServiceWorkerRegistration registration,
  ) {
    return {
      'registration_scope': registration.scope,
      'registration_has_active_worker': registration.active != null,
      'registration_has_waiting_worker': registration.waiting != null,
      'registration_has_installing_worker': registration.installing != null,
    };
  }

  Map<String, Object?> _subscriptionDetails(Object? subscription) {
    if (subscription == null) {
      return const {'has_subscription': false};
    }
    final json = _subscriptionJson(subscription);
    return {
      'has_subscription': true,
      'endpoint_origin': _endpointOrigin(json['endpoint'] as String?),
      'has_p256dh_key':
          (json['keys'] as Map<String, dynamic>?)?['p256dh'] != null,
      'has_auth_key': (json['keys'] as Map<String, dynamic>?)?['auth'] != null,
      'expiration_time': json['expirationTime'],
    };
  }
}

String? _endpointOrigin(String? endpoint) {
  if (endpoint == null || endpoint.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(endpoint);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  return '${uri.scheme}://${uri.host}';
}

Map<String, dynamic> _subscriptionJson(Object subscription) {
  final jsValue = js_util.callMethod<Object?>(subscription, 'toJSON', const []);
  return jsonDecode(jsonEncode(js_util.dartify(jsValue)))
      as Map<String, dynamic>;
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
