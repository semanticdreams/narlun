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
import 'package:narlun/random_statuses.dart';
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

  testWidgets(
    'shows status near the top and saves it through the profile form',
    (tester) async {
      final httpService = FakeProfileHttpService();
      final meModel = MeModel()
        ..setData(
          const SessionUser(
            authenticated: true,
            id: 1,
            username: 'alice',
            status: 'busy',
            hasPassword: true,
          ),
        );

      await tester.pumpWidget(_buildProfileForm(httpService, meModel));

      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Phone'), findsNothing);

      final statusField = find.byType(TextFormField).at(2);

      await tester.enterText(statusField, '  new status  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(httpService.lastPayload?['status'], 'new status');
      expect(httpService.lastPayload?.containsKey('phone'), isFalse);
      expect(meModel.data?.status, 'new status');
      expect(
        tester.testTextInput.log.where(
          (call) => call.method == 'TextInput.finishAutofillContext',
        ),
        isEmpty,
      );
    },
  );

  testWidgets('marks profile credentials for autofill save and update', (
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
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    final usernameField = tester.widget<EditableText>(
      find.byType(EditableText).at(0),
    );
    final passwordField = tester.widget<EditableText>(
      find.byType(EditableText).at(1),
    );

    expect(usernameField.autofillHints, const [AutofillHints.newUsername]);
    expect(passwordField.autofillHints, const [AutofillHints.newPassword]);
  });

  testWidgets('shows that a password is already set without prefill', (
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
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    final passwordField = tester.widget<TextField>(
      find.byType(TextField).at(1),
    );

    expect(passwordField.controller!.text, isEmpty);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('••••••••'), findsOneWidget);
    expect(
      find.text(
        'A password is already set. Leave blank to keep it, or enter a new one.',
      ),
      findsOneWidget,
    );
  });

  test('random status list contains 100 distinct options', () {
    expect(randomStatuses, hasLength(100));
    expect(randomStatuses.toSet(), hasLength(100));
    expect(
      randomStatuses.every((status) => status.length <= maxStatusLength),
      isTrue,
    );
  });

  test('random status picker avoids the excluded current status', () {
    final picked = <String>{};
    for (var i = 0; i < 32; i += 1) {
      final nextStatus = pickRandomStatus(excluding: randomStatuses.first);
      expect(nextStatus, isNot(randomStatuses.first));
      picked.add(nextStatus);
    }
    expect(picked, isNotEmpty);
  });

  testWidgets('status field has a dice button that fills a random status', (
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
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    await tester.tap(find.byKey(const Key('profile-generate-status-button')));
    await tester.pump();

    final statusField = tester.widget<TextFormField>(
      find.byType(TextFormField).at(2),
    );
    final generatedStatus = statusField.controller!.text;
    expect(generatedStatus, isNotEmpty);
    expect(randomStatuses.contains(generatedStatus), isTrue);
    expect(generatedStatus, isNot('busy'));
  });

  testWidgets('saving a username change finishes credential autofill context', (
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
          hasPassword: true,
        ),
      );

    await tester.pumpWidget(_buildProfileForm(httpService, meModel));

    await tester.enterText(find.byType(TextFormField).first, 'alice-renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(httpService.lastPayload?['username'], 'alice-renamed');
    expect(httpService.lastPayload?.containsKey('password'), isFalse);
    expect(
      tester.testTextInput.log.where(
        (call) => call.method == 'TextInput.finishAutofillContext',
      ),
      hasLength(1),
    );
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
    expect(
      tester.testTextInput.log.where(
        (call) => call.method == 'TextInput.finishAutofillContext',
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'leaves current password unchanged when password field stays blank',
    (tester) async {
      final httpService = FakeProfileHttpService();
      final meModel = MeModel()
        ..setData(
          const SessionUser(
            authenticated: true,
            id: 1,
            username: 'alice',
            status: 'busy',
            hasPassword: true,
          ),
        );

      await tester.pumpWidget(_buildProfileForm(httpService, meModel));

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(httpService.lastPayload?.containsKey('password'), isFalse);
    },
  );

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
