import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:narlun/frontend_error_reporter.dart';

void main() {
  tearDown(() {
    FrontendErrorReporter.resetForTests();
  });

  testWidgets('latest installed reporter is the only active global handler', (
    tester,
  ) async {
    var firstClientCalls = 0;
    var secondClientCalls = 0;

    final firstReporter = FrontendErrorReporter(
      client: MockClient((request) async {
        firstClientCalls += 1;
        return http.Response('', 204);
      }),
    )..install();

    final secondReporter = FrontendErrorReporter(
      client: MockClient((request) async {
        secondClientCalls += 1;
        return http.Response('', 204);
      }),
    )..install();

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.current,
        library: 'frontend_error_reporter_test',
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());

    expect(firstClientCalls, 0);
    expect(secondClientCalls, 1);

    firstReporter.dispose();
    secondReporter.dispose();
  });

  testWidgets('diagnostic logs are posted with structured details', (
    tester,
  ) async {
    Map<String, dynamic>? payload;

    final reporter = FrontendErrorReporter(
      client: MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 204);
      }),
      apiBaseUrl: '/api',
    )..install();

    await reporter.logDiagnostic(
      'install_service_initialized',
      'Initialized browser install prompt service.',
      details: {
        'is_installed': false,
        'nested': {'source': 'test'},
      },
    );
    await tester.pump();

    expect(payload?['kind'], 'install_service_initialized');
    expect(payload?['level'], 'debug');
    expect(payload?['details'], {
      'is_installed': false,
      'nested': {'source': 'test'},
    });
    expect(payload?['fingerprint'], isA<String>());

    reporter.dispose();
  });

  testWidgets(
    'failed diagnostic deliveries are retried after a later successful post',
    (tester) async {
      final payloads = <Map<String, dynamic>>[];
      final responseStatuses = <int>[500, 204, 204];

      final reporter = FrontendErrorReporter(
        client: MockClient((request) async {
          payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', responseStatuses.removeAt(0));
        }),
        apiBaseUrl: '/api',
      )..install();

      await reporter.logDiagnostic(
        'push_service_initialized',
        'Initialized browser push notifications service.',
      );
      await tester.pump();

      await reporter.logDiagnostic(
        'push_service_initialized',
        'Initialized browser push notifications service.',
      );
      await tester.pump();

      expect(payloads, hasLength(3));
      expect(payloads[0]['kind'], 'push_service_initialized');
      expect(payloads[1]['kind'], 'push_service_initialized');
      expect(payloads[2]['kind'], 'diagnostics_delivery_failed');
      expect(payloads[2]['details']['failed_kind'], 'push_service_initialized');
      expect(payloads[2]['details']['failed_level'], 'debug');
      expect(
        payloads[2]['details']['failed_message'],
        'Initialized browser push notifications service.',
      );
      expect(payloads[2]['details']['failed_route'], '/');
      expect(payloads[2]['details']['failed_at'], isA<String>());
      expect(payloads[2]['details']['delivery_status_code'], 500);

      reporter.dispose();
    },
  );
}
