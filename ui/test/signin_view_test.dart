import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/signin_view.dart';
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

class _FakeSigninHttpService extends HttpService {
  _FakeSigninHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  String? lastUsername;
  String? lastPassword;

  @override
  Future<SessionUser> signin({username, password}) async {
    lastUsername = username as String?;
    lastPassword = password as String?;
    return const SessionUser(
      authenticated: true,
      id: 1,
      username: 'alice',
      hasPassword: true,
    );
  }
}

void main() {
  testWidgets('sign in exposes username and password autofill hints', (
    tester,
  ) async {
    await tester.pumpWidget(
      Provider<HttpService>.value(
        value: _FakeSigninHttpService(),
        child: ChangeNotifierProvider(
          create: (_) => MeModel(),
          child: const MaterialApp(home: SigninView()),
        ),
      ),
    );

    final usernameField = tester.widget<TextField>(
      find.byKey(const Key('signin-username-field')),
    );
    final passwordField = tester.widget<TextField>(
      find.byKey(const Key('signin-password-field')),
    );

    expect(usernameField.autofillHints, const [AutofillHints.username]);
    expect(passwordField.autofillHints, const [AutofillHints.password]);
  });

  testWidgets('successful sign in finishes autofill save context', (
    tester,
  ) async {
    final httpService = _FakeSigninHttpService();

    await tester.pumpWidget(
      Provider<HttpService>.value(
        value: httpService,
        child: ChangeNotifierProvider(
          create: (_) => MeModel(),
          child: MaterialApp(
            routes: {'/home': (_) => const Scaffold(body: Text('Home screen'))},
            home: const SigninView(),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('signin-username-field')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const Key('signin-password-field')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('signin-submit-button')));
    await tester.pumpAndSettle();

    expect(httpService.lastUsername, 'alice');
    expect(httpService.lastPassword, 'correct horse battery staple');
    expect(
      tester.testTextInput.log.where(
        (call) => call.method == 'TextInput.finishAutofillContext',
      ),
      hasLength(1),
    );
    expect(find.text('Home screen'), findsOneWidget);
  });
}
