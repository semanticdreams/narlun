import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dialog_service.dart';
import 'http.dart';
import 'locator.dart';
import 'me_model.dart';

Future<void> expireSession(
  BuildContext context, {
  required HttpService httpService,
  String description = 'Your session has ended. Please sign in again.',
}) async {
  await locator<DialogService>().showDialog(
    title: 'Session ended',
    description: description,
  );

  await httpService.clearLocalSession();

  if (!context.mounted) {
    return;
  }

  Provider.of<MeModel>(context, listen: false).reset();
  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
}
