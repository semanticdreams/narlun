import 'models.dart';
import 'push_notifications_service.dart';

class UnsupportedPushNotificationsService extends PushNotificationsService {
  @override
  bool get isBusy => false;

  @override
  bool get isConfigured => false;

  @override
  bool get isSubscribed => false;

  @override
  bool get isSupported => false;

  @override
  bool get shouldShowPrompt => false;

  @override
  PushPermissionState get permissionState => PushPermissionState.unsupported;

  @override
  String? get statusMessage => null;

  @override
  Future<void> disableNotifications() async {}

  @override
  Future<void> enableNotifications() async {}

  @override
  void dismissPrompt() {}

  @override
  Future<void> syncSession(SessionUser? user) async {}
}

PushNotificationsService createPushNotificationsService({String? apiBaseUrl}) {
  return UnsupportedPushNotificationsService();
}
