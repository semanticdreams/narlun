import 'package:flutter/foundation.dart';

import 'app_update_service_default.dart'
    if (dart.library.html) 'app_update_service_browser.dart' as impl;

abstract class AppUpdateService extends ChangeNotifier {
  bool get isSupported;
  bool get isUpdateAvailable;
  bool get isApplyingUpdate;
  bool get shouldShowUpdatePrompt;

  Future<void> checkForUpdate();
  Future<void> applyUpdate();
}

AppUpdateService createAppUpdateService() {
  return impl.createAppUpdateService();
}
