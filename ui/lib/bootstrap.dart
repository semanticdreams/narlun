import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';

import 'app.dart';
import 'app_update_service.dart';
import 'config.dart';
import 'frontend_error_reporter.dart';
import 'http.dart';
import 'install_prompt_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'push_notifications_service.dart';
import 'push_notifications_session_bridge.dart';

Object? _e2eSemanticsHandle;
FrontendErrorReporter? _frontendErrorReporter;

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
}

Widget buildNarlunApp() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5F4484),
    brightness: Brightness.light,
  );
  final errorReporter = _frontendErrorReporter ??=
      (FrontendErrorReporter(apiBaseUrl: Environment().config.apiUrl)
        ..install());
  final meModel = MeModel();
  errorReporter.attachMeModel(meModel);
  return MultiProvider(
    providers: [
      Provider<HttpService>(
        create: (_) => HttpService(),
        dispose: (_, httpService) => httpService.close(),
      ),
      ChangeNotifierProvider<InstallPromptService>(
        lazy: false,
        create: (_) => createInstallPromptService(),
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
      ChangeNotifierProvider<MeModel>.value(value: meModel),
    ],
    child: PushNotificationsSessionBridge(
      child: MyApp(
        errorReporter: errorReporter,
        theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
      ),
    ),
  );
}

Future<void> bootstrapApp({String? environment, String? apiUrlOverride}) async {
  await initializeApp(environment: environment, apiUrlOverride: apiUrlOverride);
  runApp(buildNarlunApp());
}
