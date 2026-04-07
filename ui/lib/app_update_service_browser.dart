// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'app_update_service.dart';
import 'web_install_state_browser.dart';

const _updateCheckInterval = Duration(minutes: 20);

class BrowserAppUpdateService extends AppUpdateService {
  BrowserAppUpdateService() {
    _serviceWorkerContainer = html.window.navigator.serviceWorker;
    _isSupported = _serviceWorkerContainer != null;
    if (!_isSupported) {
      return;
    }

    _controllerChangeListener = (_) {
      if (_isApplyingUpdate || _isUpdateAvailable) {
        html.window.location.reload();
        return;
      }
      unawaited(_refreshRegistration());
    };
    _visibilityChangeListener = (_) {
      if (html.document.visibilityState == 'visible') {
        unawaited(checkForUpdate());
      }
    };
    _serviceWorkerContainer!.addEventListener(
      'controllerchange',
      _controllerChangeListener,
    );
    html.document.addEventListener(
      'visibilitychange',
      _visibilityChangeListener,
    );
    _periodicCheckTimer = Timer.periodic(_updateCheckInterval, (_) {
      unawaited(checkForUpdate());
    });
    unawaited(_initialize());
  }

  html.ServiceWorkerContainer? _serviceWorkerContainer;
  html.ServiceWorkerRegistration? _registration;
  html.EventListener? _controllerChangeListener;
  html.EventListener? _visibilityChangeListener;
  html.EventListener? _updateFoundListener;
  html.EventListener? _installingStateChangeListener;
  html.ServiceWorker? _watchedInstallingWorker;
  Timer? _periodicCheckTimer;
  bool _isSupported = false;
  bool _isUpdateAvailable = false;
  bool _isApplyingUpdate = false;
  bool _isCheckingForUpdate = false;

  @override
  bool get isSupported => _isSupported;

  @override
  bool get isUpdateAvailable => _isUpdateAvailable;

  @override
  bool get isApplyingUpdate => _isApplyingUpdate;

  Future<void> _initialize() async {
    await _refreshRegistration();
    await checkForUpdate();
  }

  @override
  Future<void> checkForUpdate() async {
    if (!_isSupported || _isCheckingForUpdate) {
      return;
    }
    _isCheckingForUpdate = true;
    try {
      final registration = await _refreshRegistration();
      if (registration == null) {
        return;
      }
      await registration.update();
      await _refreshRegistration();
    } catch (_) {
      return;
    } finally {
      _isCheckingForUpdate = false;
    }
  }

  @override
  Future<void> applyUpdate() async {
    if (!_isSupported || _isApplyingUpdate) {
      return;
    }
    final registration = await _refreshRegistration();
    final waiting = registration?.waiting;
    if (waiting == null) {
      _isUpdateAvailable = false;
      notifyListeners();
      return;
    }
    _isApplyingUpdate = true;
    notifyListeners();
    waiting.postMessage({'type': 'SKIP_WAITING'});
  }

  Future<html.ServiceWorkerRegistration?> _refreshRegistration() async {
    if (!_isSupported) {
      return null;
    }
    final registration = await _serviceWorkerContainer!.getRegistration();
    if (!identical(_registration, registration)) {
      _detachRegistrationListeners();
      _registration = registration;
      _attachRegistrationListeners(registration);
    }
    _syncWaitingState(registration);
    return registration;
  }

  void _attachRegistrationListeners(
    html.ServiceWorkerRegistration registration,
  ) {
    _updateFoundListener = (_) {
      _watchInstallingWorker(registration.installing);
      _syncWaitingState(registration);
    };
    registration.addEventListener('updatefound', _updateFoundListener);
    _watchInstallingWorker(registration.installing);
  }

  void _watchInstallingWorker(html.ServiceWorker? installing) {
    final previousListener = _installingStateChangeListener;
    if (_watchedInstallingWorker != null && previousListener != null) {
      _watchedInstallingWorker!.removeEventListener(
        'statechange',
        previousListener,
      );
    }
    if (installing == null) {
      _watchedInstallingWorker = null;
      _installingStateChangeListener = null;
      return;
    }
    _watchedInstallingWorker = installing;
    _installingStateChangeListener = (_) {
      _syncWaitingState(_registration);
    };
    installing.addEventListener('statechange', _installingStateChangeListener);
  }

  void _detachRegistrationListeners() {
    if (_registration != null && _updateFoundListener != null) {
      _registration!.removeEventListener('updatefound', _updateFoundListener);
    }
    if (_watchedInstallingWorker != null &&
        _installingStateChangeListener != null) {
      _watchedInstallingWorker!.removeEventListener(
        'statechange',
        _installingStateChangeListener,
      );
    }
    _updateFoundListener = null;
    _installingStateChangeListener = null;
    _watchedInstallingWorker = null;
  }

  void _syncWaitingState(html.ServiceWorkerRegistration? registration) {
    if (registration == null) {
      _setUpdateAvailable(false);
      return;
    }
    final hasController = _serviceWorkerContainer?.controller != null;
    final hasWaitingUpdate = hasController && registration.waiting != null;
    _setUpdateAvailable(hasWaitingUpdate);
    if (hasWaitingUpdate && detectInstalledWebApp() && !_isApplyingUpdate) {
      unawaited(applyUpdate());
    }
  }

  void _setUpdateAvailable(bool value) {
    if (_isUpdateAvailable == value) {
      return;
    }
    _isUpdateAvailable = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _periodicCheckTimer?.cancel();
    if (_serviceWorkerContainer != null && _controllerChangeListener != null) {
      _serviceWorkerContainer!.removeEventListener(
        'controllerchange',
        _controllerChangeListener,
      );
    }
    if (_visibilityChangeListener != null) {
      html.document.removeEventListener(
        'visibilitychange',
        _visibilityChangeListener,
      );
    }
    _detachRegistrationListeners();
    super.dispose();
  }
}

AppUpdateService createAppUpdateService() {
  return BrowserAppUpdateService();
}
