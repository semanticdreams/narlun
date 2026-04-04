import 'install_prompt_service.dart';

class _UnavailableInstallPromptService extends InstallPromptService {
  @override
  bool get isInstallAvailable => false;

  @override
  bool get isInstalled => false;

  @override
  bool get shouldShowSuggestion => false;

  @override
  void dismissSuggestion() {}

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    return InstallPromptOutcome.unavailable;
  }
}

InstallPromptService createInstallPromptService() {
  return _UnavailableInstallPromptService();
}
