import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/appbar_avatar.dart';
import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/install_prompt_service.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
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

class _FakeInstallPromptService extends InstallPromptService {
  @override
  bool get isInstallAvailable => false;

  @override
  bool get isInstalled => false;

  @override
  bool get shouldShowSuggestion => false;

  @override
  void dismissSuggestion() {}

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    return InstallPromptOutcome.unavailable;
  }
}

class _FakeAppBarHttpService extends HttpService {
  _FakeAppBarHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  bool clearedLocalSession = false;
  Object? signoutError;

  @override
  Future signout() async {
    if (signoutError != null) {
      await clearLocalSession();
      throw signoutError!;
    }
    await clearLocalSession();
  }

  @override
  Future<void> clearLocalSession() async {
    clearedLocalSession = true;
  }
}

void main() {
  setUp(() async {
    final dialogService = DialogService();
    await setupLocator(reset: true, dialogService: dialogService);
  });

  tearDown(() async {
    await locator.reset();
  });

  testWidgets('expired session during sign out resets the app cleanly', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    locator<DialogService>().attachNavigator(navigatorKey);
    final httpService = _FakeAppBarHttpService()
      ..signoutError = UnauthorizedResponse();
    final meModel = MeModel()
      ..setData(
        const SessionUser(
          authenticated: true,
          id: 1,
          username: 'alice',
        ),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: _FakeInstallPromptService(),
          ),
          ChangeNotifierProvider<MeModel>.value(value: meModel),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          initialRoute: '/home',
          routes: {
            '/': (_) => const Scaffold(body: Text('Welcome landing')),
            '/home': (_) => Scaffold(
                  appBar: AppBar(actions: const [AppBarAvatar()]),
                  body: const Text('Home'),
                ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Session ended'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(httpService.clearedLocalSession, isTrue);
    expect(meModel.data?.authenticated, isFalse);
    expect(find.text('Welcome landing'), findsOneWidget);
  });
}
