// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'frontend_error_reporter.dart';
import 'install_prompt_service.dart';

class BrowserInstallPromptService extends InstallPromptService {
  late final html.EventListener _beforeInstallPromptListener;
  late final html.EventListener _appInstalledListener;
  Timer? _availabilityProbeTimer;
  bool _isInstalled = false;
  bool _promptObserved = false;

  BrowserInstallPromptService() {
    _isInstalled = _detectInstalled();
    _promptObserved = _detectPromptObserved();
    _log(
      'service_initialized',
      'Initialized browser install prompt service.',
      details: _installStateDetails(),
    );
    _beforeInstallPromptListener = (html.Event event) {
      if (_isInstalled) {
        return;
      }
      _captureBrowserPrompt(event);
    };
    _appInstalledListener = (_) {
      _isInstalled = true;
      _log('app_installed', 'Browser reported the app was installed.');
      notifyListeners();
    };
    html.window.addEventListener(
      'beforeinstallprompt',
      _beforeInstallPromptListener,
    );
    html.window.addEventListener('appinstalled', _appInstalledListener);
    _scheduleAvailabilityProbe();
  }

  @override
  bool get isInstallAvailable => false;

  @override
  bool get isInstalled => _isInstalled;

  @override
  bool get shouldShowSuggestion => false;

  @override
  void dismissSuggestion() {}

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    _log(
      'prompt_unavailable',
      'Install prompt request was unavailable.',
      details: _installStateDetails(),
    );
    return InstallPromptOutcome.unavailable;
  }

  bool _detectInstalled() {
    final standaloneMediaQuery = html.window.matchMedia(
      '(display-mode: standalone)',
    );
    final navigatorStandalone =
        js_util.getProperty<bool?>(html.window.navigator, 'standalone') == true;
    final bootstrapInstalled =
        js_util.getProperty<Object?>(
              html.window,
              '__narlunInstalledFromBootstrap',
            ) !=
            null &&
        js_util.callMethod<bool>(
          html.window,
          '__narlunInstalledFromBootstrap',
          const [],
        );
    return standaloneMediaQuery.matches ||
        navigatorStandalone ||
        bootstrapInstalled;
  }

  bool _detectPromptObserved() {
    final observer = js_util.getProperty<Object?>(
      html.window,
      '__narlunObservedBeforeInstallPrompt',
    );
    if (observer == null) {
      return false;
    }
    return js_util.callMethod<bool>(
      html.window,
      '__narlunObservedBeforeInstallPrompt',
      const [],
    );
  }

  void _scheduleAvailabilityProbe() {
    _availabilityProbeTimer?.cancel();
    _availabilityProbeTimer = Timer(const Duration(seconds: 5), () {
      if (_isInstalled || _promptObserved) {
        return;
      }
      _log(
        'availability_missing',
        'Install prompt is still unavailable after startup.',
        details: _installStateDetails(),
      );
    });
  }

  void _captureBrowserPrompt(html.Event event) {
    _promptObserved = true;
    _log(
      'beforeinstallprompt_observed',
      'Observed the browser beforeinstallprompt event.',
      details: _installStateDetails(),
    );
    notifyListeners();
  }

  Map<String, Object?> _installStateDetails({Map<String, Object?>? extra}) {
    final standaloneMediaQuery = html.window.matchMedia(
      '(display-mode: standalone)',
    );
    return {
      'is_installed': _isInstalled,
      'is_install_available': isInstallAvailable,
      'should_show_suggestion': shouldShowSuggestion,
      'beforeinstallprompt_observed': _promptObserved,
      'is_secure_context': html.window.isSecureContext == true,
      'service_worker_supported': html.window.navigator.serviceWorker != null,
      'display_mode_standalone': standaloneMediaQuery.matches,
      'navigator_standalone':
          js_util.getProperty<bool?>(html.window.navigator, 'standalone') ==
          true,
      'document_referrer': html.document.referrer,
      ...?extra,
    };
  }

  void _log(String kind, String message, {Map<String, Object?>? details}) {
    logFrontendDiagnostic(
      'install_$kind',
      message,
      details: _installStateDetails(extra: details),
    );
  }

  @override
  void dispose() {
    _availabilityProbeTimer?.cancel();
    html.window.removeEventListener(
      'beforeinstallprompt',
      _beforeInstallPromptListener,
    );
    html.window.removeEventListener('appinstalled', _appInstalledListener);
    super.dispose();
  }
}

InstallPromptService createInstallPromptService() {
  return BrowserInstallPromptService();
}
