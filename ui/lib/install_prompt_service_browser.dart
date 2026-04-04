// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js_util' as js_util;

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
  bool _isInstalled = false;

  BrowserInstallPromptService() {
    _isInstalled = _detectInstalled();
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
      notifyListeners();
    };
    html.window.addEventListener(
      'beforeinstallprompt',
      _beforeInstallPromptListener,
    );
    html.window.addEventListener('appinstalled', _appInstalledListener);
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
    notifyListeners();
  }

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    final deferredPrompt = _deferredPrompt;
    if (deferredPrompt == null || _isInstalled) {
      return InstallPromptOutcome.unavailable;
    }
    _deferredPrompt = null;

    final outcome = await deferredPrompt.prompt();
    if (outcome == InstallPromptOutcome.accepted) {
      _isInstalled = true;
      _clearDismissedUntil();
      notifyListeners();
      return InstallPromptOutcome.accepted;
    }

    dismissSuggestion();
    return InstallPromptOutcome.dismissed;
  }

  bool _detectInstalled() {
    final standaloneMediaQuery = html.window.matchMedia(
      '(display-mode: standalone)',
    );
    final navigatorStandalone =
        js_util.getProperty<bool?>(html.window.navigator, 'standalone') ==
        true;
    return standaloneMediaQuery.matches || navigatorStandalone;
  }

  void _clearDismissedUntil() {
    html.window.localStorage.remove(_installPromptDismissedUntilKey);
  }

  void _captureBrowserPrompt(html.Event event) {
    js_util.callMethod<Object>(event, 'preventDefault', const []);
    final Object promptEvent = event;
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
    notifyListeners();
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
              js_util.getProperty<num?>(html.window, '__narlunInstallPromptCalls') ??
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
