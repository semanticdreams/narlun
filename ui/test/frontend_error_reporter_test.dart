import 'dart:async';

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
}
