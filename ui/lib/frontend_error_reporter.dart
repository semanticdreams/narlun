import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'client_observability.dart';
import 'config.dart';
import 'frontend_runtime_info.dart';
import 'http_client_default.dart'
    if (dart.library.html) 'http_client_browser.dart'
    as session_http;
import 'me_model.dart';

const _maxEventsPerSession = 200;
const _fingerprintCooldown = Duration(seconds: 10);

class FrontendErrorReporter {
  FrontendErrorReporter({
    http.Client? client,
    String? environment,
    String? release,
    String? apiBaseUrl,
  }) : _client = client ?? session_http.createHttpClient(),
       _environment = environment ?? Environment.PROD,
       _release = release ?? const String.fromEnvironment('APP_RELEASE'),
       _endpoint = Uri.parse(
         '${apiBaseUrl ?? Environment().config.apiUrl}/client-errors',
       ),
       _clientSessionId = getOrCreateClientSessionId();

  final http.Client _client;
  final String _environment;
  final String _release;
  final Uri _endpoint;
  final String _clientSessionId;
  final Map<String, DateTime> _lastSentAtByFingerprint = {};
  static FrontendErrorReporter? _currentReporter;
  static void Function(FlutterErrorDetails details)?
  _previousFlutterErrorHandler;
  static ErrorCallback? _previousPlatformErrorHandler;
  static bool _handlersInstalled = false;

  int _sentEvents = 0;
  int? _userId;
  String _currentRoute = '/';
  MeModel? _attachedMeModel;
  VoidCallback? _meModelListener;
  bool _disposed = false;

  void install() {
    if (!_handlersInstalled) {
      _previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        final previousFlutterErrorHandler = _previousFlutterErrorHandler;
        if (previousFlutterErrorHandler != null) {
          previousFlutterErrorHandler(details);
        } else {
          FlutterError.presentError(details);
        }
        final reporter = _currentReporter;
        if (reporter != null) {
          unawaited(
            reporter._reportFlutterError(details, kind: 'flutter_error'),
          );
        }
      };

      _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher
          .instance
          .onError = (Object error, StackTrace stackTrace) {
        final reporter = _currentReporter;
        if (reporter != null) {
          unawaited(
            reporter.report(
              error,
              stackTrace,
              kind: 'platform_uncaught',
              message: error.toString(),
            ),
          );
        }
        return _previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
      };

      _handlersInstalled = true;
    }

    _disposed = false;
    _currentReporter = this;
  }

  static void resetForTests() {
    if (_handlersInstalled) {
      FlutterError.onError = _previousFlutterErrorHandler;
      PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
      _handlersInstalled = false;
      _previousFlutterErrorHandler = null;
      _previousPlatformErrorHandler = null;
    }
    _currentReporter = null;
  }

  void attachMeModel(MeModel meModel) {
    if (identical(_attachedMeModel, meModel)) {
      _syncUser(meModel);
      return;
    }
    if (_attachedMeModel != null && _meModelListener != null) {
      _attachedMeModel!.removeListener(_meModelListener!);
    }
    _attachedMeModel = meModel;
    _meModelListener = () => _syncUser(meModel);
    _syncUser(meModel);
    meModel.addListener(_meModelListener!);
  }

  NavigatorObserver createNavigatorObserver() {
    return _ErrorReportingNavigatorObserver(this);
  }

  void updateRoute(String? routeName) {
    final normalized = routeName?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    if (_currentRoute != normalized) {
      unawaited(
        logDiagnostic(
          'route_changed',
          'Navigated to a new route.',
          details: {'route': normalized},
        ),
      );
    }
    _currentRoute = normalized;
  }

  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String kind,
    String? message,
  }) async {
    await _sendEvent(
      kind: kind,
      level: 'error',
      message: message ?? error.toString(),
      stack: (stackTrace ?? StackTrace.current).toString(),
    );
  }

  Future<void> logDiagnostic(
    String kind,
    String message, {
    Map<String, Object?>? details,
  }) async {
    await _sendEvent(
      kind: kind,
      level: 'debug',
      message: message,
      stack: StackTrace.current.toString(),
      details: details,
    );
  }

  Future<void> _sendEvent({
    required String kind,
    required String level,
    required String message,
    required String stack,
    Map<String, Object?>? details,
  }) async {
    if (_disposed) {
      return;
    }
    try {
      final resolvedMessage = _truncate(message.trim(), 1000);
      final resolvedStack = _truncate(stack.trim(), 8000);
      if (resolvedMessage.isEmpty || resolvedStack.isEmpty) {
        return;
      }

      final fingerprint = _fingerprintFor(
        kind,
        resolvedMessage,
        resolvedStack,
        _currentRoute,
      );
      if (_shouldDrop(fingerprint)) {
        return;
      }

      final payload = <String, Object?>{
        'ts': DateTime.now().toUtc().toIso8601String(),
        'app': 'narlun-ui',
        'env': _environment,
        'release': _release.isEmpty ? null : _release,
        'route': _truncate(_currentRoute, 512),
        'user_id': _userId,
        'client_session_id': _clientSessionId,
        'fingerprint': fingerprint,
        'kind': kind,
        'level': level,
        'message': resolvedMessage,
        'stack': resolvedStack,
        'details': _sanitizeDetails(details),
        'user_agent': _truncate(getUserAgent(), 512),
        'screen': getScreenInfo(),
      };

      await _client.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/json',
          clientSessionHeader: _clientSessionId,
        },
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (identical(_currentReporter, this)) {
      _currentReporter = null;
    }
    if (_attachedMeModel != null && _meModelListener != null) {
      _attachedMeModel!.removeListener(_meModelListener!);
      _attachedMeModel = null;
      _meModelListener = null;
    }
    _client.close();
  }

  Future<void> _reportFlutterError(
    FlutterErrorDetails details, {
    required String kind,
  }) {
    return report(
      details.exception,
      details.stack,
      kind: kind,
      message: details.exceptionAsString(),
    );
  }

  void _syncUser(MeModel meModel) {
    _userId = meModel.data?.id;
  }

  bool _shouldDrop(String fingerprint) {
    final now = DateTime.now();
    _lastSentAtByFingerprint.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _fingerprintCooldown,
    );
    if (_sentEvents >= _maxEventsPerSession) {
      return true;
    }
    final lastSentAt = _lastSentAtByFingerprint[fingerprint];
    if (lastSentAt != null &&
        now.difference(lastSentAt) < _fingerprintCooldown) {
      return true;
    }

    _lastSentAtByFingerprint[fingerprint] = now;
    _sentEvents += 1;
    return false;
  }

  String _fingerprintFor(
    String kind,
    String message,
    String stack,
    String route,
  ) {
    final topFrames = stack
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(6)
        .join('\n');
    final source = '$kind|$route|$message|$topFrames';
    return _fnv1a(source).toRadixString(16);
  }

  int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  String _truncate(String? value, int maxLength) {
    if (value == null) {
      return '';
    }
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }
}

void logFrontendDiagnostic(
  String kind,
  String message, {
  Map<String, Object?>? details,
}) {
  final reporter = FrontendErrorReporter._currentReporter;
  if (reporter == null) {
    return;
  }
  unawaited(reporter.logDiagnostic(kind, message, details: details));
}

Map<String, Object?>? _sanitizeDetails(Map<String, Object?>? details) {
  if (details == null || details.isEmpty) {
    return null;
  }
  final sanitized = <String, Object?>{};
  details.forEach((key, value) {
    sanitized[_truncateStatic(key.trim(), 64)] = _sanitizeDetailValue(value);
  });
  sanitized.removeWhere((key, value) => key.isEmpty || value == null);
  return sanitized.isEmpty ? null : sanitized;
}

Object? _sanitizeDetailValue(Object? value) {
  if (value == null || value is bool || value is num) {
    return value;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return _truncateStatic(trimmed, 512);
  }
  if (value is Map<Object?, Object?>) {
    final nested = <String, Object?>{};
    value.forEach((nestedKey, nestedValue) {
      if (nestedKey is! String) {
        return;
      }
      nested[_truncateStatic(nestedKey.trim(), 64)] = _sanitizeDetailValue(
        nestedValue,
      );
    });
    nested.removeWhere(
      (key, nestedValue) => key.isEmpty || nestedValue == null,
    );
    return nested.isEmpty ? null : nested;
  }
  if (value is Iterable<Object?>) {
    final nested = value
        .map(_sanitizeDetailValue)
        .where((nestedValue) => nestedValue != null)
        .take(20)
        .toList();
    return nested.isEmpty ? null : nested;
  }
  return _truncateStatic(value.toString(), 512);
}

String _truncateStatic(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return value.substring(0, maxLength);
}

class _ErrorReportingNavigatorObserver extends NavigatorObserver {
  _ErrorReportingNavigatorObserver(this.reporter);

  final FrontendErrorReporter reporter;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    reporter.updateRoute(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    reporter.updateRoute(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    reporter.updateRoute(previousRoute?.settings.name);
    super.didPop(route, previousRoute);
  }
}
