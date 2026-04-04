import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';

import 'app.dart';
import 'config.dart';
import 'locator.dart';
import 'me_model.dart';

Object? _e2eSemanticsHandle;

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
}

Widget buildNarlunApp() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF5F4484),
    brightness: Brightness.light,
  );
  return ChangeNotifierProvider(
    create: (_) => MeModel(),
    child: MyApp(
      theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
    ),
  );
}

Future<void> bootstrapApp({String? environment, String? apiUrlOverride}) async {
  await initializeApp(environment: environment, apiUrlOverride: apiUrlOverride);
  runApp(buildNarlunApp());
}
