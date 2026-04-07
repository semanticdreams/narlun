import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'install_prompt_service.dart';
import 'me_model.dart';

class InstallPromptSessionBridge extends StatefulWidget {
  const InstallPromptSessionBridge({super.key, required this.child});

  final Widget child;

  @override
  State<InstallPromptSessionBridge> createState() =>
      _InstallPromptSessionBridgeState();
}

class _InstallPromptSessionBridgeState
    extends State<InstallPromptSessionBridge> {
  MeModel? _meModel;
  InstallPromptService? _installPromptService;
  bool _dialogVisible = false;
  String? _lastPresentedHandoffUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final meModel = Provider.of<MeModel>(context);
    final installPromptService = Provider.of<InstallPromptService>(
      context,
      listen: false,
    );
    if (!identical(_meModel, meModel) ||
        !identical(_installPromptService, installPromptService)) {
      _meModel?.removeListener(_handleSessionChanged);
      _installPromptService?.removeListener(_handleInstallPromptChanged);
      _meModel = meModel;
      _installPromptService = installPromptService;
      _meModel?.addListener(_handleSessionChanged);
      _installPromptService?.addListener(_handleInstallPromptChanged);
      unawaited(_installPromptService?.syncSession(_meModel?.data));
      _scheduleHandoffDialogCheck();
    }
  }

  @override
  void dispose() {
    _meModel?.removeListener(_handleSessionChanged);
    _installPromptService?.removeListener(_handleInstallPromptChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    unawaited(_installPromptService?.syncSession(_meModel?.data));
  }

  void _handleInstallPromptChanged() {
    _scheduleHandoffDialogCheck();
  }

  void _scheduleHandoffDialogCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_maybeShowHandoffDialog());
    });
  }

  Future<void> _maybeShowHandoffDialog() async {
    final installPromptService = _installPromptService;
    final handoffUrl = installPromptService?.installSessionHandoffUrl;
    if (installPromptService == null ||
        handoffUrl == null ||
        handoffUrl.isEmpty ||
        _dialogVisible ||
        _lastPresentedHandoffUrl == handoffUrl) {
      return;
    }

    _dialogVisible = true;
    _lastPresentedHandoffUrl = handoffUrl;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Open installed app'),
          content: const Text(
            'Narlun was installed. Open the installed app to continue there with your current session.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('dismiss'),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('open'),
              child: const Text('Open app'),
            ),
          ],
        );
      },
    );
    _dialogVisible = false;
    if (!mounted) {
      return;
    }
    if (action == 'open') {
      await installPromptService.openInstallSessionHandoff();
    }
    installPromptService.dismissInstallSessionHandoff();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
