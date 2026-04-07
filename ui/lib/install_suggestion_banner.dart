import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_route_state.dart';
import 'install_prompt_service.dart';
import 'install_suggestion_rules.dart';
import 'route_utils.dart';

class InstallSuggestionBannerFrame extends StatelessWidget {
  const InstallSuggestionBannerFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppRouteState, InstallPromptService>(
      builder: (context, routeState, installPromptService, _) {
        final routeUri = routeState.routeUri;
        final suggestion = installPromptService.suggestion;
        final showBanner =
            suggestion != null &&
            routeUri != null &&
            shouldShowPersistentInstallSuggestionForRoute(routeUri);
        return Column(
          children: [
            Expanded(child: child),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: showBanner
                  ? _InstallSuggestionBanner(
                      suggestion: suggestion,
                      onDismiss: installPromptService.dismissSuggestion,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

class _InstallSuggestionBanner extends StatelessWidget {
  const _InstallSuggestionBanner({
    required this.suggestion,
    required this.onDismiss,
  });

  final InstallSuggestion suggestion;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Material(
        elevation: 4,
        color: colorScheme.surface,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.install_mobile_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  key: const ValueKey('install-suggestion-banner'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      suggestion.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(suggestion.message),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDismiss,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
