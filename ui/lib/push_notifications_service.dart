import 'package:flutter/foundation.dart';

import 'models.dart';
import 'push_notifications_service_default.dart'
    if (dart.library.html) 'push_notifications_service_browser.dart' as impl;

enum PushPermissionState {
  unsupported,
  defaultState,
  granted,
  denied,
}

abstract class PushNotificationsService extends ChangeNotifier {
  bool get isSupported;
  bool get isConfigured;
  bool get isSubscribed;
  bool get isBusy;
  bool get shouldShowPrompt;
  PushPermissionState get permissionState;
  String? get statusMessage;

  Future<void> syncSession(SessionUser? user);
  Future<void> enableNotifications();
  Future<void> disableNotifications();
  void dismissPrompt();
}

PushNotificationsService createPushNotificationsService({String? apiBaseUrl}) {
  return impl.createPushNotificationsService(apiBaseUrl: apiBaseUrl);
}
