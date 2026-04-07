// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:http/http.dart' as http;

import 'frontend_error_reporter.dart';
import 'http_client_browser.dart' as session_http;
import 'install_prompt_service.dart';
import 'install_suggestion_rules.dart';
import 'web_install_state_browser.dart';

const _installSuggestionDismissedKey = 'narlun_install_suggestion_dismissed';

class BrowserInstallPromptService extends InstallPromptService {
  BrowserInstallPromptService({required this.apiBaseUrl})
    : _client = session_http.createHttpClient() {
    _isInstalled = _detectInstalled();
    _promptObserved = _detectPromptObserved();
    _suggestionDismissed = _readSuggestionDismissed();
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

  final String apiBaseUrl;
  final http.Client _client;
  late final html.EventListener _beforeInstallPromptListener;
  late final html.EventListener _appInstalledListener;
  Timer? _availabilityProbeTimer;
  bool _isInstalled = false;
  bool _promptObserved = false;
  bool _suggestionDismissed = false;

  @override
  bool get isInstallAvailable => false;

  @override
  bool get isInstalled => _isInstalled;

  @override
  InstallSuggestion? get suggestion => resolveInstallSuggestion(
    userAgent: html.window.navigator.userAgent,
    isInstalled: _isInstalled,
    dismissed: _suggestionDismissed,
    isSecureContext: html.window.isSecureContext == true,
    serviceWorkerSupported: html.window.navigator.serviceWorker != null,
  );

  @override
  bool get canOpenInstalledApp => !isStandaloneWebAppContext();

  @override
  void dismissSuggestion() {
    if (_suggestionDismissed) {
      return;
    }
    _suggestionDismissed = true;
    try {
      html.window.localStorage[_installSuggestionDismissedKey] = '1';
    } catch (_) {}
    _log('suggestion_dismissed', 'Dismissed the manual install suggestion.');
    notifyListeners();
  }

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    _log(
      'prompt_unavailable',
      'Install prompt request was unavailable.',
      details: _installStateDetails(),
    );
    return InstallPromptOutcome.unavailable;
  }

  @override
  Future<void> openInstalledApp({String? nextRoute}) async {
    if (!canOpenInstalledApp) {
      return;
    }
    final resolvedNextRoute = nextRoute != null && nextRoute.isNotEmpty
        ? nextRoute
        : _currentBrowserRoute();
    try {
      final response = await _client.post(
        Uri.parse('$apiBaseUrl/users/install-session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'next_route': resolvedNextRoute}),
      );
      if (response.statusCode != 200) {
        _log(
          'session_handoff_prepare_failed',
          'Server did not accept the installed app handoff request.',
          details: {'status_code': response.statusCode},
        );
        throw StateError('Installed app handoff is unavailable right now.');
      }
      final responseBody = jsonDecode(response.body);
      if (responseBody is! Map<String, dynamic>) {
        throw StateError('Installed app handoff response was invalid.');
      }
      final claimUrl = responseBody['claim_url'];
      if (claimUrl is! String || claimUrl.isEmpty) {
        throw StateError('Installed app handoff link was missing.');
      }
      _log(
        'session_handoff_opened',
        'Attempted to open the installed app handoff URL.',
        details: {'next_route': resolvedNextRoute},
      );
      html.window.open(claimUrl, '_blank');
    } catch (error) {
      _log(
        'session_handoff_prepare_failed',
        'Preparing the installed app handoff URL failed.',
        details: {'error': error.toString(), 'next_route': resolvedNextRoute},
      );
      rethrow;
    }
  }

  bool _detectInstalled() {
    return detectInstalledWebApp();
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

  bool _readSuggestionDismissed() {
    try {
      return html.window.localStorage[_installSuggestionDismissedKey] == '1';
    } catch (_) {
      return false;
    }
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

  String _currentBrowserRoute() {
    final currentLocation = Uri.base;
    return currentLocation.path.isEmpty
        ? '/'
        : Uri(
            path: currentLocation.path,
            queryParameters: currentLocation.queryParameters.isEmpty
                ? null
                : currentLocation.queryParameters,
          ).toString();
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
    _client.close();
    html.window.removeEventListener(
      'beforeinstallprompt',
      _beforeInstallPromptListener,
    );
    html.window.removeEventListener('appinstalled', _appInstalledListener);
    super.dispose();
  }
}

InstallPromptService createInstallPromptService({String? apiBaseUrl}) {
  return BrowserInstallPromptService(apiBaseUrl: apiBaseUrl ?? '');
}
