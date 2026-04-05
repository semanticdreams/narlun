import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:narlun/install_prompt_actions.dart';
import 'package:narlun/install_prompt_service.dart';

class _ThrowingInstallPromptService extends InstallPromptService {
  @override
  bool get isInstallAvailable => true;

  @override
  bool get isInstalled => false;

  @override
  bool get shouldShowSuggestion => true;

  @override
  void dismissSuggestion() {}

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    throw StateError('prompt failed');
  }
}

void main() {
  testWidgets('shows a snackbar when install prompting fails', (tester) async {
    final installPromptService = _ThrowingInstallPromptService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  await handleInstallRequest(context, installPromptService);
                },
                child: const Text('Install'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Install'));
    await tester.pump();

    expect(
      find.text('Could not start installation right now.'),
      findsOneWidget,
    );
  });
}
