import 'package:flutter/foundation.dart';

import 'install_suggestion_rules.dart';
import 'install_prompt_service_default.dart'
    if (dart.library.html) 'install_prompt_service_browser.dart'
    as impl;

enum InstallPromptOutcome { accepted, dismissed, unavailable }

abstract class InstallPromptService extends ChangeNotifier {
  bool get isInstallAvailable;
  bool get isInstalled;
  bool get canOpenInstalledApp => false;
  bool get shouldShowSuggestion => suggestion != null;
  InstallSuggestion? get suggestion => null;

  Future<InstallPromptOutcome> requestInstall();
  void dismissSuggestion();
  Future<void> openInstalledApp({String? nextRoute}) async {}
}

InstallPromptService createInstallPromptService({String? apiBaseUrl}) {
  return impl.createInstallPromptService(apiBaseUrl: apiBaseUrl);
}
