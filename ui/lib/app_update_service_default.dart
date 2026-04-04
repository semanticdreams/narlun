import 'app_update_service.dart';

class DefaultAppUpdateService extends AppUpdateService {
  @override
  bool get isSupported => false;

  @override
  bool get isUpdateAvailable => false;

  @override
  bool get isApplyingUpdate => false;

  @override
  Future<void> applyUpdate() async {}

  @override
  Future<void> checkForUpdate() async {}
}

AppUpdateService createAppUpdateService() {
  return DefaultAppUpdateService();
}
