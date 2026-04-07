import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';

import 'app.dart';
import 'app_update_service.dart';
import 'config.dart';
import 'frontend_error_reporter.dart';
import 'http.dart';
import 'install_prompt_service.dart';
import 'invite_qr_cache.dart';
import 'location_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'nearby_feed_model.dart';
import 'push_notifications_service.dart';
import 'push_notifications_session_bridge.dart';
import 'room_messages_cache.dart';
import 'rooms_feed_model.dart';
import 'feed_session_bridge.dart';

Object? _e2eSemanticsHandle;
FrontendErrorReporter? _frontendErrorReporter;
const _initialSessionTimeout = Duration(seconds: 3);

Future<void> initializeApp({
  String? environment,
  String? apiUrlOverride,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('ENABLE_E2E_SEMANTICS', defaultValue: false)) {
    _e2eSemanticsHandle ??= WidgetsBinding.instance.ensureSemantics();
  }
  setPathUrlStrategy();

  final selectedEnvironment =
      (environment ??
              const String.fromEnvironment(
                'ENV',
                defaultValue: Environment.PROD,
              ))
          .toUpperCase();
  final selectedApiUrl =
      apiUrlOverride ??
      const String.fromEnvironment('API_URL', defaultValue: '');

  Environment().initConfig(selectedEnvironment, apiUrlOverride: selectedApiUrl);
  await setupLocator(reset: true);
  _frontendErrorReporter?.dispose();
  _frontendErrorReporter = FrontendErrorReporter(
    environment: selectedEnvironment,
    apiBaseUrl: Environment().config.apiUrl,
  )..install();
  unawaited(
    _frontendErrorReporter!.logDiagnostic(
      'bootstrap_initialized',
      'Initialized frontend diagnostics reporting.',
      details: {
        'environment': selectedEnvironment,
        'api_base_url': Environment().config.apiUrl,
      },
    ),
  );
}

Widget buildNarlunApp({SessionUser? initialSessionUser}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5F4484),
    brightness: Brightness.light,
  );
  final errorReporter = _frontendErrorReporter ??= (FrontendErrorReporter(
    apiBaseUrl: Environment().config.apiUrl,
  )..install());
  final meModel = MeModel(data: initialSessionUser);
  errorReporter.attachMeModel(meModel);
  return MultiProvider(
    providers: [
      Provider<HttpService>(
        create: (_) => HttpService(),
        dispose: (_, httpService) => httpService.close(),
      ),
      Provider<InviteQrCache>(create: (_) => InviteQrCache()),
      Provider<RoomMessagesCache>(create: (_) => RoomMessagesCache()),
      ChangeNotifierProvider<InstallPromptService>(
        lazy: false,
        create: (_) =>
            createInstallPromptService(apiBaseUrl: Environment().config.apiUrl),
      ),
      ChangeNotifierProvider<AppUpdateService>(
        lazy: false,
        create: (_) => createAppUpdateService(),
      ),
      ChangeNotifierProvider<PushNotificationsService>(
        lazy: false,
        create: (_) => createPushNotificationsService(
          apiBaseUrl: Environment().config.apiUrl,
        ),
      ),
      ChangeNotifierProvider<NearbyFeedModel>(
        create: (context) => NearbyFeedModel(
          httpService: context.read<HttpService>(),
          locationService: createLocationService(),
        ),
      ),
      ChangeNotifierProvider<RoomsFeedModel>(
        create: (context) =>
            RoomsFeedModel(httpService: context.read<HttpService>()),
      ),
      ChangeNotifierProvider<MeModel>.value(value: meModel),
    ],
    child: FeedSessionBridge(
      child: PushNotificationsSessionBridge(
        child: MyApp(
          errorReporter: errorReporter,
          theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
        ),
      ),
    ),
  );
}

Future<SessionUser?> _loadInitialSessionUser() async {
  final httpService = HttpService();
  try {
    return await httpService
        .fetch_me(silentErrors: true, reconnectWebsocket: false)
        .timeout(_initialSessionTimeout);
  } catch (_) {
    return null;
  } finally {
    httpService.close();
  }
}

Future<void> bootstrapApp({String? environment, String? apiUrlOverride}) async {
  await initializeApp(environment: environment, apiUrlOverride: apiUrlOverride);
  final initialSessionUser = await _loadInitialSessionUser();
  runApp(buildNarlunApp(initialSessionUser: initialSessionUser));
}
