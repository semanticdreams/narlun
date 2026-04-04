// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/profile_form.dart';
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

  Map<String, dynamic>? lastPayload;

  @override
  Future<SessionUser> update_profile(data) async {
    lastPayload = Map<String, dynamic>.from(data as Map);
    return SessionUser(
      authenticated: true,
      id: 1,
      username: data['username'] as String?,
      status: data['status'] as String?,
      phone: data['phone'] as String?,
      hasPassword: true,
    );
  }
}

Widget _buildProfileForm(FakeProfileHttpService httpService, MeModel meModel) {
  return Provider<HttpService>.value(
    value: httpService,
    child: ChangeNotifierProvider<MeModel>.value(
      value: meModel,
      child: const MaterialApp(
        home: Scaffold(
          body: ProfileForm(
            data: SessionUser(
              authenticated: true,
              id: 1,
              username: 'alice',
              status: 'busy',
              phone: '123',
              hasPassword: true,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() async {
    await setupLocator(reset: true, dialogService: DialogService());
  });

  tearDown(() async {
    await locator.reset();
  });

  testWidgets('shows status near the top and saves it through the profile form', (
    tester,
  ) async {
    final httpService = FakeProfileHttpService();
    final meModel = MeModel()
      ..setData(
        const SessionUser(
          authenticated: true,
          id: 1,
          username: 'alice',
          status: 'busy',
          phone: '123',
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);

    final statusField = find.byType(TextFormField).at(2);
    final phoneField = find.byType(TextFormField).at(3);

    final statusTopLeft = tester.getTopLeft(statusField);
    final phoneTopLeft = tester.getTopLeft(phoneField);
    expect(statusTopLeft.dy, lessThan(phoneTopLeft.dy));

    await tester.enterText(statusField, '  new status  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(httpService.lastPayload?['status'], 'new status');
    expect(meModel.data?.status, 'new status');
  });

  testWidgets('generates a memorable passphrase and saves it as password', (
    tester,
  ) async {
    final httpService = FakeProfileHttpService();
    final meModel = MeModel()
      ..setData(
        const SessionUser(
          authenticated: true,
          id: 1,
          username: 'alice',
          status: 'busy',
          phone: '123',
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    await tester.tap(find.byKey(const Key('profile-generate-password-button')));
    await tester.pump();

    final passwordField = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    expect(passwordField.controller!.text.split(' '), hasLength(8));
    final editablePasswordField = tester.widget<EditableText>(
      find.byType(EditableText).at(0),
    );
    expect(editablePasswordField.obscureText, isFalse);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(httpService.lastPayload?['password'], isA<String>());
    expect(
      (httpService.lastPayload?['password'] as String).split(' '),
      hasLength(8),
    );
  });

  testWidgets('leaves current password unchanged when password field stays blank', (
    tester,
  ) async {
    final httpService = FakeProfileHttpService();
    final meModel = MeModel()
      ..setData(
        const SessionUser(
          authenticated: true,
          id: 1,
          username: 'alice',
          status: 'busy',
          phone: '123',
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(httpService.lastPayload?.containsKey('password'), isFalse);
  });

  testWidgets('shows a local validation error for a short password', (
    tester,
  ) async {
    final httpService = FakeProfileHttpService();
    final meModel = MeModel()
      ..setData(
        const SessionUser(
          authenticated: true,
          id: 1,
          username: 'alice',
          status: 'busy',
          phone: '123',
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    await tester.enterText(find.byType(TextFormField).at(1), 'short');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(httpService.lastPayload, isNull);
  });
}
