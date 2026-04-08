import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_update_service.dart';

class AppUpdateBanner extends StatelessWidget {
  final Widget child;

  const AppUpdateBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppUpdateService>(
      builder: (context, updateService, _) {
        return Stack(
          children: [
            Positioned.fill(child: child),
            if (updateService.isSupported &&
                updateService.shouldShowUpdatePrompt &&
                updateService.isUpdateAvailable)
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Material(
                      elevation: 6,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.system_update_alt_rounded),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'A newer version of Narlun is ready. Reload to update.',
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: updateService.isApplyingUpdate
                                  ? null
                                  : () {
                                      unawaited(updateService.applyUpdate());
                                    },
                              child: Text(
                                updateService.isApplyingUpdate
                                    ? 'Reloading...'
                                    : 'Reload',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
