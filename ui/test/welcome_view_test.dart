import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/welcome_view.dart';
import 'package:narlun/websocket.dart';

class _DummyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}

class _FakeWebsocketService extends WebsocketService {
  _FakeWebsocketService()
    : super(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => throw UnimplementedError(),
      );
}

class FakeBootstrapHttpService extends HttpService {
  FakeBootstrapHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  final Queue<Future<SessionUser> Function(bool silentErrors)>
  _fetchMeHandlers = Queue<Future<SessionUser> Function(bool silentErrors)>();

  void enqueueFetchMe(Future<SessionUser> Function(bool silentErrors) handler) {
    _fetchMeHandlers.add(handler);
  }

  @override
  Future<SessionUser> fetch_me({
    bool silentErrors = false,
    bool reconnectWebsocket = true,
  }) async {
    return _fetchMeHandlers.removeFirst()(silentErrors);
  }
}

Widget _buildWelcomeApp(FakeBootstrapHttpService httpService) {
  return Provider<HttpService>.value(
    value: httpService,
    child: ChangeNotifierProvider(
      create: (_) => MeModel(),
      child: MaterialApp(
        routes: {
          '/': (_) => const WelcomeView(),
          '/signup': (_) => const Scaffold(body: Text('Signup page')),
          '/home': (_) => const Scaffold(body: Text('Home page')),
        },
      ),
    ),
  );
}

void main() {
  testWidgets('bootstrap shows retry state and retries automatically', (
    tester,
  ) async {
    final httpService = FakeBootstrapHttpService()
      ..enqueueFetchMe((silentErrors) async {
        expect(silentErrors, isTrue);
        throw ServerError(500);
      })
      ..enqueueFetchMe((silentErrors) async {
        expect(silentErrors, isTrue);
        return SessionUser.unauthenticated();
      });

    await tester.pumpWidget(_buildWelcomeApp(httpService));
    await tester.pump();

    expect(
      find.text('Still trying to connect. Trying again in 1s...'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text(
        'Narlun is having trouble starting right now. We will keep trying.',
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Signup page'), findsOneWidget);
  });

  testWidgets('bootstrap allows an immediate manual retry', (tester) async {
    final completer = Completer<SessionUser>();
    final httpService = FakeBootstrapHttpService()
      ..enqueueFetchMe((_) async => throw StateError('offline'))
      ..enqueueFetchMe((_) => completer.future);

    await tester.pumpWidget(_buildWelcomeApp(httpService));
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    completer.complete(SessionUser.unauthenticated());
    await tester.pumpAndSettle();

    expect(find.text('Signup page'), findsOneWidget);
  });
}
