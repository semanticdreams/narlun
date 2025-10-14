import 'package:flutter/material.dart';

import 'locator.dart';
import 'dialog_service.dart';
import 'alert_request.dart';
import 'alert_response.dart';

class DialogManager extends StatefulWidget {
  final Widget child;

  //DialogManager({Key? key, this.child}) : super(key: key);
  DialogManager({Key? key, required this.child}) : super(key: key);

  _DialogManagerState createState() => _DialogManagerState();
}

class _DialogManagerState extends State<DialogManager> {
  DialogService _dialogService = locator<DialogService>();
  var confirmed = false;

  @override
  void initState() {
    super.initState();
    _dialogService.registerDialogListener(_showDialog);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _showDialog(AlertRequest request) async {
    confirmed = false;
    await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
              title: Text(request.title),
              content: Text(request.description),
              actions: [
                TextButton(
                    child: Text(request.buttonTitle),
                    onPressed: () {
                      confirmed = true;
                      Navigator.of(context).pop();
                    }),
              ]);
        });
    _dialogService.dialogComplete(AlertResponse(confirmed: confirmed));
  }
}
