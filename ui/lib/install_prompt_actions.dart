import 'package:flutter/material.dart';

import 'install_prompt_service.dart';

Future<void> handleInstallRequest(
  BuildContext context,
  InstallPromptService installPromptService,
) async {
  final outcome = await installPromptService.requestInstall();
  if (!context.mounted) {
    return;
  }

  String? message;
  switch (outcome) {
    case InstallPromptOutcome.accepted:
      message = 'Narlun is installing.';
      break;
    case InstallPromptOutcome.dismissed:
      message = 'Install dismissed for now.';
      break;
    case InstallPromptOutcome.unavailable:
      message = 'Install is not available right now.';
      break;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
