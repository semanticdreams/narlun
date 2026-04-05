// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'frontend_error_reporter.dart';
import 'install_prompt_service.dart';

const _installPromptDismissedUntilKey =
    'narlun.installPromptSuggestionDismissedUntil';
const _enableE2eSemantics = bool.fromEnvironment(
  'ENABLE_E2E_SEMANTICS',
  defaultValue: false,
);

class _DeferredInstallPrompt {
  final Future<InstallPromptOutcome> Function() prompt;

  const _DeferredInstallPrompt(this.prompt);
}

class BrowserInstallPromptService extends InstallPromptService {
  _DeferredInstallPrompt? _deferredPrompt;
  late final html.EventListener _beforeInstallPromptListener;
  late final html.EventListener _appInstalledListener;
  Timer? _availabilityProbeTimer;
  bool _isInstalled = false;

  BrowserInstallPromptService() {
    _isInstalled = _detectInstalled();
    final deferredPromptEvent = _consumeBootstrapDeferredPrompt();
    if (deferredPromptEvent != null && !_isInstalled) {
      _capturePromptEventObject(deferredPromptEvent, fromBootstrap: true);
    }
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
      _deferredPrompt = null;
      _clearDismissedUntil();
      _log('app_installed', 'Browser reported the app was installed.');
      notifyListeners();
    };
    html.window.addEventListener(
      'beforeinstallprompt',
      _beforeInstallPromptListener,
    );
    html.window.addEventListener('appinstalled', _appInstalledListener);
    _scheduleAvailabilityProbe();
    _installE2eHook();
  }

  @override
  bool get isInstallAvailable => !_isInstalled && _deferredPrompt != null;

  @override
  bool get isInstalled => _isInstalled;

  @override
  bool get shouldShowSuggestion => isInstallAvailable && !_isDismissedForNow;

  bool get _isDismissedForNow {
    final value = html.window.localStorage[_installPromptDismissedUntilKey];
    if (value == null) {
      return false;
    }
    final dismissedUntil = DateTime.tryParse(value);
    if (dismissedUntil == null) {
      html.window.localStorage.remove(_installPromptDismissedUntilKey);
      return false;
    }
    if (dismissedUntil.isAfter(DateTime.now().toUtc())) {
      return true;
    }
    html.window.localStorage.remove(_installPromptDismissedUntilKey);
    return false;
  }

  @override
  void dismissSuggestion() {
    final dismissedUntil = DateTime.now()
        .toUtc()
        .add(const Duration(days: 7))
        .toIso8601String();
    html.window.localStorage[_installPromptDismissedUntilKey] = dismissedUntil;
    _log('prompt_dismissed', 'Dismissed the install prompt suggestion.');
    notifyListeners();
  }

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    final deferredPrompt = _deferredPrompt;
    if (deferredPrompt == null || _isInstalled) {
      _log(
        'prompt_unavailable',
        'Install prompt request was unavailable.',
        details: _installStateDetails(
          extra: {'has_deferred_prompt': deferredPrompt != null},
        ),
      );
      return InstallPromptOutcome.unavailable;
    }
    _deferredPrompt = null;

    late final InstallPromptOutcome outcome;
    try {
      outcome = await deferredPrompt.prompt();
    } catch (error) {
      _deferredPrompt = deferredPrompt;
      _log(
        'prompt_failed',
        'Browser install prompt failed.',
        details: _installStateDetails(extra: {'error': error.toString()}),
      );
      notifyListeners();
      rethrow;
    }
    if (outcome == InstallPromptOutcome.accepted) {
      _isInstalled = true;
      _clearDismissedUntil();
      _log('prompt_accepted', 'Accepted the browser install prompt.');
      notifyListeners();
      return InstallPromptOutcome.accepted;
    }

    _log('prompt_rejected', 'Dismissed the browser install prompt.');
    dismissSuggestion();
    return InstallPromptOutcome.dismissed;
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

  void _clearDismissedUntil() {
    html.window.localStorage.remove(_installPromptDismissedUntilKey);
  }

  void _scheduleAvailabilityProbe() {
    _availabilityProbeTimer?.cancel();
    _availabilityProbeTimer = Timer(const Duration(seconds: 5), () {
      if (_isInstalled || _deferredPrompt != null) {
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
    js_util.callMethod<Object>(event, 'preventDefault', const []);
    _capturePromptEventObject(event);
  }

  Object? _consumeBootstrapDeferredPrompt() {
    final consumer = js_util.getProperty<Object?>(
      html.window,
      '__narlunConsumeDeferredInstallPrompt',
    );
    if (consumer == null) {
      return null;
    }
    return js_util.callMethod<Object?>(
      html.window,
      '__narlunConsumeDeferredInstallPrompt',
      const [],
    );
  }

  void _capturePromptEventObject(
    Object promptEvent, {
    bool fromBootstrap = false,
  }) {
    _deferredPrompt = _DeferredInstallPrompt(() async {
      await js_util.promiseToFuture<Object>(
        js_util.callMethod<Object>(promptEvent, 'prompt', const []),
      );
      final choice = await js_util.promiseToFuture<Object>(
        js_util.getProperty<Object>(promptEvent, 'userChoice'),
      );
      final outcome =
          js_util.getProperty<String?>(choice, 'outcome') ?? 'dismissed';
      return outcome == 'accepted'
          ? InstallPromptOutcome.accepted
          : InstallPromptOutcome.dismissed;
    });
    _log(
      'beforeinstallprompt_captured',
      'Captured the browser beforeinstallprompt event.',
      details: _installStateDetails(extra: {'from_bootstrap': fromBootstrap}),
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
      'dismissed_for_now': _isDismissedForNow,
      'has_deferred_prompt': _deferredPrompt != null,
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

  void _installE2eHook() {
    if (!_enableE2eSemantics) {
      return;
    }
    js_util.setProperty(html.window, '__narlunInstallPromptCalls', 0);
    js_util.setProperty(
      html.window,
      '__narlunSimulateInstallPrompt',
      js_util.allowInterop((String outcome) {
        _deferredPrompt = _DeferredInstallPrompt(() async {
          final currentCalls =
              js_util.getProperty<num?>(
                html.window,
                '__narlunInstallPromptCalls',
              ) ??
              0;
          js_util.setProperty(
            html.window,
            '__narlunInstallPromptCalls',
            currentCalls + 1,
          );
          return outcome == 'accepted'
              ? InstallPromptOutcome.accepted
              : InstallPromptOutcome.dismissed;
        });
        notifyListeners();
      }),
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
    if (_enableE2eSemantics) {
      js_util.setProperty(html.window, '__narlunSimulateInstallPrompt', null);
    }
    super.dispose();
  }
}

InstallPromptService createInstallPromptService() {
  return BrowserInstallPromptService();
}
