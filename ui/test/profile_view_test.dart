import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/install_prompt_service.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/profile_view.dart';
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

class FakeProfileHttpService extends HttpService {
  FakeProfileHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );
}

class FakeInstallPromptService extends InstallPromptService {
  FakeInstallPromptService({this.available = false});

  bool available;
  int requestInstallCalls = 0;

  @override
  bool get isInstallAvailable => available;

  @override
  bool get isInstalled => false;

  @override
  bool get shouldShowSuggestion => false;

  @override
  void dismissSuggestion() {}

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    requestInstallCalls += 1;
    return InstallPromptOutcome.accepted;
  }
}

void main() {
  setUp(() async {
    await setupLocator(reset: true, dialogService: DialogService());
  });

  tearDown(() async {
    await locator.reset();
  });

  testWidgets('shows an install action in profile when install is available', (
    tester,
  ) async {
    final installPromptService = FakeInstallPromptService(available: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: FakeProfileHttpService()),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: installPromptService,
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(
                  authenticated: true,
                  id: 1,
                  username: 'alice',
                ),
              ),
          ),
        ],
        child: const MaterialApp(home: ProfileView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Install app'), findsOneWidget);

    await tester.ensureVisible(find.text('Install app'));
    await tester.tap(find.text('Install app'));
    await tester.pumpAndSettle();

    expect(installPromptService.requestInstallCalls, 1);
    expect(find.text('Narlun is installing.'), findsOneWidget);
  });
}
