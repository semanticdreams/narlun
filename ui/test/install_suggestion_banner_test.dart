import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:narlun/app_route_state.dart';
import 'package:narlun/install_prompt_service.dart';
import 'package:narlun/install_suggestion_banner.dart';
import 'package:narlun/install_suggestion_rules.dart';

class _FakeInstallPromptService extends InstallPromptService {
  _FakeInstallPromptService({InstallSuggestion? suggestion})
    : _suggestion = suggestion;

  InstallSuggestion? _suggestion;
  int dismissCalls = 0;

  @override
  bool get isInstallAvailable => false;

  @override
  bool get isInstalled => false;

  @override
  InstallSuggestion? get suggestion => _suggestion;

  @override
  void dismissSuggestion() {
    dismissCalls += 1;
    _suggestion = null;
    notifyListeners();
  }

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    return InstallPromptOutcome.unavailable;
  }
}

void main() {
  Widget buildFrame({
    required AppRouteState routeState,
    required InstallPromptService installPromptService,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppRouteState>.value(value: routeState),
        ChangeNotifierProvider<InstallPromptService>.value(
          value: installPromptService,
        ),
      ],
      child: MaterialApp(
        home: InstallSuggestionBannerFrame(
          child: Scaffold(
            body: ListView(
              children: const [
                SizedBox(height: 1200, child: Text('Scrollable content')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the install suggestion below app content on app routes', (
    tester,
  ) async {
    final routeState = AppRouteState()..updateRouteName('/rooms');
    final installPromptService = _FakeInstallPromptService(
      suggestion: const InstallSuggestion(
        title: 'Install Narlun',
        message: 'Open the browser menu, then choose Install app.',
      ),
    );

    await tester.pumpWidget(
      buildFrame(
        routeState: routeState,
        installPromptService: installPromptService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Install Narlun'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.drag(find.byType(Scrollable), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Install Narlun'), findsOneWidget);
  });

  testWidgets('hides the install suggestion on the opening route', (
    tester,
  ) async {
    final routeState = AppRouteState()..updateRouteName('/');
    final installPromptService = _FakeInstallPromptService(
      suggestion: const InstallSuggestion(
        title: 'Install Narlun',
        message: 'Open the browser menu, then choose Install app.',
      ),
    );

    await tester.pumpWidget(
      buildFrame(
        routeState: routeState,
        installPromptService: installPromptService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Install Narlun'), findsNothing);
  });

  testWidgets('dismisses the install suggestion permanently for the service', (
    tester,
  ) async {
    final routeState = AppRouteState()..updateRouteName('/nearby');
    final installPromptService = _FakeInstallPromptService(
      suggestion: const InstallSuggestion(
        title: 'Install Narlun',
        message: 'Open the browser menu, then choose Install app.',
      ),
    );

    await tester.pumpWidget(
      buildFrame(
        routeState: routeState,
        installPromptService: installPromptService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(installPromptService.dismissCalls, 1);
    expect(find.text('Install Narlun'), findsNothing);
  });
}
