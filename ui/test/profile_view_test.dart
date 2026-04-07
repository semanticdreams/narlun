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
import 'package:narlun/profile_view.dart';
import 'package:narlun/push_notifications_service.dart';
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

  int updateProfileCalls = 0;
  Map<String, dynamic>? lastProfilePayload;
  int submitFeedbackCalls = 0;
  String? lastFeedbackMessage;
  String? lastFeedbackRoute;
  String? lastFeedbackSource;
  bool? lastFeedbackSilentErrors;

  @override
  Future<SessionUser> update_profile(data) async {
    updateProfileCalls += 1;
    lastProfilePayload = Map<String, dynamic>.from(data as Map);
    return SessionUser(
      authenticated: true,
      id: 1,
      username: data['username'] as String?,
      status: data['status'] as String?,
      hasPassword: true,
    );
  }

  @override
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

class FakePushNotificationsService extends PushNotificationsService {
  FakePushNotificationsService({
    this.supported = true,
    this.configured = true,
    this.subscribed = false,
    this.message = 'Notifications are off for this browser.',
  });

  final bool supported;
  final bool configured;
  final bool subscribed;
  final String? message;
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  bool get isBusy => false;

  @override
  bool get isConfigured => configured;

  @override
  bool get isSubscribed => subscribed;

  @override
  bool get isSupported => supported;

  @override
  bool get shouldShowPrompt => false;

  @override
  PushPermissionState get permissionState => PushPermissionState.defaultState;

  @override
  String? get statusMessage => message;

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

class RecordingDialogService extends DialogService {
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

class _ProfileRouteHost extends StatefulWidget {
  const _ProfileRouteHost();

  @override
  State<_ProfileRouteHost> createState() => _ProfileRouteHostState();
}

class _ProfileRouteHostState extends State<_ProfileRouteHost> {
  bool _didPushProfile = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPushProfile) {
      return;
    }
    _didPushProfile = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProfileView(),
          settings: const RouteSettings(name: '/profile'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('Root screen'));
  }
}

void main() {
  setUp(() async {
    await setupLocator(reset: true, dialogService: DialogService());
  });

  tearDown(() async {
    await locator.reset();
  });

  Widget buildProfileApp({
    required FakeProfileHttpService httpService,
    required InstallPromptService installPromptService,
    required PushNotificationsService pushNotificationsService,
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
        ChangeNotifierProvider(
          create: (_) => MeModel()
            ..setData(
              const SessionUser(
                authenticated: true,
                id: 1,
                username: 'alice',
                status: 'busy',
                hasPassword: true,
              ),
            ),
        ),
      ],
      child: const MaterialApp(home: _ProfileRouteHost()),
    );
  }

  testWidgets('shows an install action in profile when install is available', (
    tester,
  ) async {
    final installPromptService = FakeInstallPromptService(available: true);
    final pushNotificationsService = FakePushNotificationsService();
    final httpService = FakeProfileHttpService();

    await tester.pumpWidget(
      buildProfileApp(
        httpService: httpService,
        installPromptService: installPromptService,
        pushNotificationsService: pushNotificationsService,
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

  testWidgets('shows a generic upload error when picture preparation fails', (
    tester,
  ) async {
    final installPromptService = FakeInstallPromptService(available: false);
    final pushNotificationsService = FakePushNotificationsService();
    final httpService = FakeProfileHttpService();
    final dialogService = RecordingDialogService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: installPromptService,
          ),
          ChangeNotifierProvider<PushNotificationsService>.value(
            value: pushNotificationsService,
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(
                  authenticated: true,
                  id: 1,
                  username: 'alice',
                  status: 'busy',
                  hasPassword: true,
                ),
              ),
          ),
        ],
        child: MaterialApp(
          home: ProfileView(
            dialogService: dialogService,
            imagePicker: () async =>
                throw StateError('Could not prepare the selected picture.'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Upload picture'));
    await tester.pumpAndSettle();

    expect(dialogService.callCount, 1);
    expect(dialogService.lastTitle, 'Upload failed');
    expect(dialogService.lastDescription, 'Upload failed. Try again later.');
  });

  testWidgets('shows notification controls in profile when supported', (
    tester,
  ) async {
    final pushNotificationsService = FakePushNotificationsService();
    final httpService = FakeProfileHttpService();

    await tester.pumpWidget(
      buildProfileApp(
        httpService: httpService,
        installPromptService: FakeInstallPromptService(available: false),
        pushNotificationsService: pushNotificationsService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn on notifications'), findsOneWidget);
    expect(
      find.text('Notifications are off for this browser.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();

    expect(pushNotificationsService.enableCalls, 1);
  });

  testWidgets('profile app bar avatar menu still submits feedback', (
    tester,
  ) async {
    final pushNotificationsService = FakePushNotificationsService();
    final httpService = FakeProfileHttpService();

    await tester.pumpWidget(
      buildProfileApp(
        httpService: httpService,
        installPromptService: FakeInstallPromptService(available: false),
        pushNotificationsService: pushNotificationsService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('feedback-message-field')),
      'Profile edits feel weird when the keyboard opens.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(httpService.submitFeedbackCalls, 1);
    expect(
      httpService.lastFeedbackMessage,
      'Profile edits feel weird when the keyboard opens.',
    );
    expect(httpService.lastFeedbackRoute, '/profile');
    expect(httpService.lastFeedbackSource, 'account_menu');
    expect(httpService.lastFeedbackSilentErrors, isTrue);
    expect(find.text('Feedback sent. Thank you.'), findsOneWidget);
  });

  testWidgets('discarding edited profile changes pops back without saving', (
    tester,
  ) async {
    final httpService = FakeProfileHttpService();

    await tester.pumpWidget(
      buildProfileApp(
        httpService: httpService,
        installPromptService: FakeInstallPromptService(available: false),
        pushNotificationsService: FakePushNotificationsService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'bob',
    );
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(httpService.updateProfileCalls, 0);
    expect(find.text('Root screen'), findsOneWidget);
  });

  testWidgets('saving edited profile changes pops back after save', (
    tester,
  ) async {
    final httpService = FakeProfileHttpService();

    await tester.pumpWidget(
      buildProfileApp(
        httpService: httpService,
        installPromptService: FakeInstallPromptService(available: false),
        pushNotificationsService: FakePushNotificationsService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Status'),
      'away',
    );
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(httpService.updateProfileCalls, 1);
    expect(httpService.lastProfilePayload?['status'], 'away');
    expect(find.text('Root screen'), findsOneWidget);
  });

  testWidgets('canceling the unsaved changes prompt keeps profile open', (
    tester,
  ) async {
    final httpService = FakeProfileHttpService();

    await tester.pumpWidget(
      buildProfileApp(
        httpService: httpService,
        installPromptService: FakeInstallPromptService(available: false),
        pushNotificationsService: FakePushNotificationsService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'bob',
    );
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Save changes?'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    expect(httpService.updateProfileCalls, 0);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
  });
}
