import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/signup_view.dart';
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

class _FakeHttpService extends HttpService {
  _FakeHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );
}

void main() {
  testWidgets('signup username generator uses the dice icon and fills a username', (
    tester,
  ) async {
    await tester.pumpWidget(
      Provider<HttpService>.value(
        value: _FakeHttpService(),
        child: ChangeNotifierProvider(
          create: (_) => MeModel(),
          child: const MaterialApp(home: SignupView()),
        ),
      ),
    );

    final iconButton = tester.widget<IconButton>(
      find.byKey(const Key('signup-generate-username-button')),
    );
    final icon = iconButton.icon as Icon;
    expect(icon.icon, Icons.casino_outlined);

    await tester.tap(find.byKey(const Key('signup-generate-username-button')));
    await tester.pump();

    final textField = tester.widget<TextField>(
      find.byKey(const Key('signup-username-field')),
    );
    expect(textField.controller?.text.isNotEmpty, isTrue);
  });
}
