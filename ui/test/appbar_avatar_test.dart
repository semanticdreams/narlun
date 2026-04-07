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

  int submitFeedbackCalls = 0;
  String? lastFeedbackMessage;
  String? lastFeedbackRoute;
  String? lastFeedbackSource;
  bool? lastFeedbackSilentErrors;

  @override
  // ignore: non_constant_identifier_names
  Future<String?> submit_feedback({
    required String message,
    required String source,
    String? route,
    Map<String, Object?>? details,
    bool silentErrors = false,
  }) async {
    submitFeedbackCalls += 1;
    lastFeedbackMessage = message;
    lastFeedbackRoute = route;
    lastFeedbackSource = source;
    lastFeedbackSilentErrors = silentErrors;
    return 'request-1';
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

  testWidgets('opens settings from the avatar menu', (tester) async {
    final httpService = _FakeAppBarHttpService();
    final meModel = MeModel()
      ..setData(
        const SessionUser(authenticated: true, id: 1, username: 'alice'),
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
          initialRoute: '/home',
          routes: {
            '/home': (_) => Scaffold(
              appBar: AppBar(actions: const [AppBarAvatar()]),
              body: const Text('Home'),
            ),
            '/settings': (_) => const Scaffold(body: Text('Settings screen')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings screen'), findsOneWidget);
  });

  testWidgets('submits feedback from the avatar menu', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    locator<DialogService>().attachNavigator(navigatorKey);
    final httpService = _FakeAppBarHttpService();
    final meModel = MeModel()
      ..setData(
        const SessionUser(authenticated: true, id: 1, username: 'alice'),
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
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('feedback-message-field')),
      'Nearby stayed empty even though another user was close by.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(httpService.submitFeedbackCalls, 1);
    expect(
      httpService.lastFeedbackMessage,
      'Nearby stayed empty even though another user was close by.',
    );
    expect(httpService.lastFeedbackRoute, '/home');
    expect(httpService.lastFeedbackSource, 'account_menu');
    expect(httpService.lastFeedbackSilentErrors, isTrue);
    expect(find.text('Feedback sent. Thank you.'), findsOneWidget);
  });
}
