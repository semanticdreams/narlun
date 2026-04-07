import 'package:flutter/foundation.dart';

import 'install_suggestion_rules.dart';
import 'install_prompt_service_default.dart'
    if (dart.library.html) 'install_prompt_service_browser.dart' as impl;

enum InstallPromptOutcome {
  accepted,
  dismissed,
  unavailable,
}

abstract class InstallPromptService extends ChangeNotifier {
  bool get isInstallAvailable;
  bool get isInstalled;
  bool get shouldShowSuggestion => suggestion != null;
  InstallSuggestion? get suggestion => null;

  Future<InstallPromptOutcome> requestInstall();
  void dismissSuggestion();
}

InstallPromptService createInstallPromptService() {
  return impl.createInstallPromptService();
}
