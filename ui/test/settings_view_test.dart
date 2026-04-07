// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/alert_response.dart';
import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/install_prompt_service.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/push_notifications_service.dart';
import 'package:narlun/settings_view.dart';
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
  _FakeInstallPromptService({
    this.available = false,
    this.canOpenInstalled = false,
    this.openInstalledAppError,
  });

  final bool available;
  final bool canOpenInstalled;
  final Object? openInstalledAppError;
  int requestInstallCalls = 0;
  int openInstalledAppCalls = 0;
  String? lastOpenedNextRoute;

  @override
  bool get isInstallAvailable => available;

  @override
  bool get isInstalled => false;

  @override
  bool get canOpenInstalledApp => canOpenInstalled;

  @override
  bool get shouldShowSuggestion => false;

  @override
  void dismissSuggestion() {}

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    requestInstallCalls += 1;
    return InstallPromptOutcome.accepted;
  }

  @override
  Future<void> openInstalledApp({String? nextRoute}) async {
    openInstalledAppCalls += 1;
    lastOpenedNextRoute = nextRoute;
    if (openInstalledAppError != null) {
      throw openInstalledAppError!;
    }
  }
}

class _FakePushNotificationsService extends PushNotificationsService {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  bool get isBusy => false;

  @override
  bool get isConfigured => true;

  @override
  bool get isSubscribed => false;

  @override
  bool get isSupported => true;

  @override
  bool get shouldShowPrompt => false;

  @override
  PushPermissionState get permissionState => PushPermissionState.defaultState;

  @override
  String? get statusMessage => 'Notifications are off for this browser.';

  @override
  Future<void> disableNotifications() async {
    disableCalls += 1;
  }

  @override
  Future<void> enableNotifications() async {
    enableCalls += 1;
  }

  @override
  void dismissPrompt() {}

  @override
  Future<void> syncSession(SessionUser? user) async {}
}

class _FakeSettingsHttpService extends HttpService {
  _FakeSettingsHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  bool clearedLocalSession = false;
  Object? signoutError;
  int deleteAccountCalls = 0;

  @override
  Future signout() async {
    if (signoutError != null) {
      await clearLocalSession();
      throw signoutError!;
    }
    await clearLocalSession();
  }

  @override
  Future delete_account() async {
    deleteAccountCalls += 1;
    await clearLocalSession();
  }

  @override
  Future<void> clearLocalSession() async {
    clearedLocalSession = true;
  }
}

class _RecordingDialogService extends DialogService {
  String? lastTitle;
  String? lastDescription;
  int callCount = 0;

  @override
  Future<AlertResponse> showDialog({
    required String title,
    required String description,
    String buttonTitle = 'OK',
  }) async {
    lastTitle = title;
    lastDescription = description;
    callCount += 1;
    return AlertResponse(confirmed: true);
  }
}

void main() {
  setUp(() async {
    await setupLocator(reset: true, dialogService: DialogService());
  });

  tearDown(() async {
    await locator.reset();
  });

  Widget buildSettingsApp({
    required _FakeSettingsHttpService httpService,
    required InstallPromptService installPromptService,
    required PushNotificationsService pushNotificationsService,
    MeModel? meModel,
  }) {
    return MultiProvider(
      providers: [
        Provider<HttpService>.value(value: httpService),
        ChangeNotifierProvider<InstallPromptService>.value(
          value: installPromptService,
        ),
        ChangeNotifierProvider<PushNotificationsService>.value(
          value: pushNotificationsService,
        ),
        ChangeNotifierProvider<MeModel>.value(
          value:
              meModel ??
              (MeModel()..setData(
                const SessionUser(
                  authenticated: true,
                  id: 1,
                  username: 'alice',
                  hasPassword: true,
                ),
              )),
        ),
      ],
      child: MaterialApp(
        initialRoute: '/settings',
        routes: {
          '/': (_) => const Scaffold(body: Text('Welcome landing')),
          '/settings': (_) => const SettingsView(),
        },
      ),
    );
  }

  testWidgets('settings shows notification and account actions', (
    tester,
  ) async {
    final pushNotificationsService = _FakePushNotificationsService();
    final httpService = _FakeSettingsHttpService();

    await tester.pumpWidget(
      buildSettingsApp(
        httpService: httpService,
        installPromptService: _FakeInstallPromptService(available: false),
        pushNotificationsService: pushNotificationsService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn on notifications'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);

    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();

    expect(pushNotificationsService.enableCalls, 1);
  });

  testWidgets('expired session during sign out resets the app cleanly', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    locator<DialogService>().attachNavigator(navigatorKey);
    final httpService = _FakeSettingsHttpService()
      ..signoutError = UnauthorizedResponse();
    final meModel = MeModel()
      ..setData(
        const SessionUser(authenticated: true, id: 1, username: 'alice'),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: _FakeInstallPromptService(available: false),
          ),
          ChangeNotifierProvider<PushNotificationsService>.value(
            value: _FakePushNotificationsService(),
          ),
          ChangeNotifierProvider<MeModel>.value(value: meModel),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          initialRoute: '/settings',
          routes: {
            '/': (_) => const Scaffold(body: Text('Welcome landing')),
            '/settings': (_) => const SettingsView(),
          },
        ),
      ),
    );
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

  testWidgets('delete account is available from settings', (tester) async {
    final httpService = _FakeSettingsHttpService();
    final meModel = MeModel()
      ..setData(
        const SessionUser(authenticated: true, id: 1, username: 'alice'),
      );

    await tester.pumpWidget(
      buildSettingsApp(
        httpService: httpService,
        installPromptService: _FakeInstallPromptService(available: false),
        pushNotificationsService: _FakePushNotificationsService(),
        meModel: meModel,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Delete account?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(httpService.deleteAccountCalls, 1);
    expect(httpService.clearedLocalSession, isTrue);
    expect(meModel.data?.authenticated, isFalse);
    expect(find.text('Welcome landing'), findsOneWidget);
  });

  testWidgets('settings can show install action', (tester) async {
    final installPromptService = _FakeInstallPromptService(available: true);
    final pushNotificationsService = _FakePushNotificationsService();
    final httpService = _FakeSettingsHttpService();

    await tester.pumpWidget(
      buildSettingsApp(
        httpService: httpService,
        installPromptService: installPromptService,
        pushNotificationsService: pushNotificationsService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Install app'), findsOneWidget);

    await tester.tap(find.text('Install app'));
    await tester.pumpAndSettle();

    expect(installPromptService.requestInstallCalls, 1);
    expect(find.text('Narlun is installing.'), findsOneWidget);
  });

  testWidgets('settings can open installed app with home handoff', (
    tester,
  ) async {
    final installPromptService = _FakeInstallPromptService(
      available: false,
      canOpenInstalled: true,
    );
    final pushNotificationsService = _FakePushNotificationsService();
    final httpService = _FakeSettingsHttpService();

    await tester.pumpWidget(
      buildSettingsApp(
        httpService: httpService,
        installPromptService: installPromptService,
        pushNotificationsService: pushNotificationsService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open installed app'), findsOneWidget);

    await tester.tap(find.text('Open installed app'));
    await tester.pumpAndSettle();

    expect(installPromptService.openInstalledAppCalls, 1);
    expect(installPromptService.lastOpenedNextRoute, '/home');
    expect(
      find.text(
        'If the app is installed, it should open there signed into Narlun.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('installed app handoff errors surface a dialog', (tester) async {
    final dialogService = _RecordingDialogService();
    await setupLocator(reset: true, dialogService: dialogService);
    final httpService = _FakeSettingsHttpService();
    final installPromptService = _FakeInstallPromptService(
      available: false,
      canOpenInstalled: true,
      openInstalledAppError: StateError('Failed to open'),
    );

    await tester.pumpWidget(
      buildSettingsApp(
        httpService: httpService,
        installPromptService: installPromptService,
        pushNotificationsService: _FakePushNotificationsService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open installed app'));
    await tester.pumpAndSettle();

    expect(dialogService.callCount, 1);
    expect(dialogService.lastTitle, 'Could not open installed app');
    expect(
      dialogService.lastDescription,
      'The installed app could not be opened right now. Try again.',
    );
  });

  testWidgets('notification update errors surface a dialog', (tester) async {
    final dialogService = _RecordingDialogService();
    await setupLocator(reset: true, dialogService: dialogService);
    final httpService = _FakeSettingsHttpService();
    final pushNotificationsService = _ThrowingPushNotificationsService();

    await tester.pumpWidget(
      buildSettingsApp(
        httpService: httpService,
        installPromptService: _FakeInstallPromptService(available: false),
        pushNotificationsService: pushNotificationsService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();

    expect(dialogService.callCount, 1);
    expect(dialogService.lastTitle, 'Could not update notifications');
    expect(
      dialogService.lastDescription,
      'Notification settings could not be updated right now.',
    );
  });
}

class _ThrowingPushNotificationsService extends _FakePushNotificationsService {
  @override
  Future<void> enableNotifications() async {
    throw StateError('No permission');
  }
}
