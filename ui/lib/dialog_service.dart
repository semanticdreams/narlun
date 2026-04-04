import 'dart:async';
import 'package:flutter/material.dart';
import 'alert_request.dart';
import 'alert_response.dart';

class DialogService {
  GlobalKey<NavigatorState>? _navigatorKey;

  void attachNavigator(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  Future<AlertResponse> showDialog({
    required String title,
    required String description,
    String buttonTitle = 'OK',
  }) async {
    final context = _navigatorKey?.currentContext;
    if (context == null) {
      return AlertResponse(confirmed: false);
    }
    final request = AlertRequest(
      title: title,
      description: description,
      buttonTitle: buttonTitle,
    );
    final response = await showGeneralDialog<AlertResponse>(
      context: context,
      barrierDismissible: false,
      barrierLabel: request.title,
      pageBuilder: (dialogContext, _, __) {
        return AlertDialog(
          title: Text(request.title),
          content: Text(request.description),
          actions: [
            TextButton(
              child: Text(request.buttonTitle),
              onPressed: () {
                Navigator.of(dialogContext).pop(AlertResponse(confirmed: true));
              },
            ),
          ],
        );
      },
    );
    return response ?? AlertResponse(confirmed: false);
  }
}
