import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';

import 'app.dart';
import 'config.dart';
import 'locator.dart';
import 'me_model.dart';

Future<void> initializeApp({
  String? environment,
  String? apiUrlOverride,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();

  final selectedEnvironment = (environment ??
          const String.fromEnvironment(
            'ENV',
            defaultValue: Environment.PROD,
          ))
      .toUpperCase();
  final selectedApiUrl = apiUrlOverride ??
      const String.fromEnvironment('API_URL', defaultValue: '');

  Environment().initConfig(
    selectedEnvironment,
    apiUrlOverride: selectedApiUrl,
  );
  await setupLocator(reset: true);
}

Widget buildNarlunApp() {
  return ChangeNotifierProvider(
    create: (_) => MeModel(),
    child: MyApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
    ),
  );
}

Future<void> bootstrapApp({
  String? environment,
  String? apiUrlOverride,
}) async {
  await initializeApp(
    environment: environment,
    apiUrlOverride: apiUrlOverride,
  );
  runApp(buildNarlunApp());
}
