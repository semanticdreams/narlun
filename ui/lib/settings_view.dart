import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'appbar_avatar.dart';
import 'dialog_service.dart';
import 'http.dart';
import 'install_prompt_actions.dart';
import 'install_prompt_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'push_notifications_service.dart';
import 'route_utils.dart';
import 'session_actions.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  Future<void> _signOut(BuildContext context) async {
    final httpService = Provider.of<HttpService>(context, listen: false);
    try {
      await httpService.signout();
      if (!context.mounted) {
        return;
      }
      Provider.of<MeModel>(context, listen: false).reset();
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } on UnauthorizedResponse {
      if (!context.mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } catch (error) {
      await showActionErrorDialog(
        locator<DialogService>(),
        title: 'Could not sign out',
        error: error,
        fallbackDescription:
            'Sign out could not be completed right now. Try again.',
      );
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final httpService = Provider.of<HttpService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This removes your account and avatar. Rooms that end up with no meaningful membership left may also disappear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await httpService.delete_account();
      if (!context.mounted) {
        return;
      }
      Provider.of<MeModel>(context, listen: false).reset();
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } on UnauthorizedResponse {
      if (!context.mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } catch (error) {
      await showActionErrorDialog(
        locator<DialogService>(),
        title: 'Could not delete account',
        error: error,
        fallbackDescription:
            'Your account could not be deleted right now. Try again.',
      );
    }
  }

  Future<void> _toggleNotifications(
    BuildContext context,
    PushNotificationsService pushService,
  ) async {
    try {
      if (pushService.isSubscribed) {
        await pushService.disableNotifications();
      } else {
        await pushService.enableNotifications();
      }
    } catch (error) {
      await showActionErrorDialog(
        locator<DialogService>(),
        title: 'Could not update notifications',
        error: error,
        fallbackDescription:
            'Notification settings could not be updated right now.',
      );
    }
  }

  Future<void> _openInstalledApp(
    BuildContext context,
    InstallPromptService installPromptService,
  ) async {
    try {
      await installPromptService.openInstalledApp(nextRoute: '/home');
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'If the app is installed, it should open there signed into Narlun.',
            ),
          ),
        );
    } catch (error) {
      await showActionErrorDialog(
        locator<DialogService>(),
        title: 'Could not open installed app',
        error: error,
        fallbackDescription:
            'The installed app could not be opened right now. Try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Provider.of<MeModel>(context).data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [AppBarAvatar()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (me?.authenticated == true)
              Consumer<PushNotificationsService>(
                builder: (context, pushService, child) {
                  if (!pushService.isSupported) {
                    return const SizedBox.shrink();
                  }
                  final statusMessage = pushService.statusMessage;
                  final canShowAction =
                      pushService.isConfigured || pushService.isSubscribed;
                  return _SettingsSection(
                    title: 'Notifications',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (canShowAction)
                          OutlinedButton.icon(
                            onPressed: pushService.isBusy
                                ? null
                                : () => _toggleNotifications(
                                    context,
                                    pushService,
                                  ),
                            icon: Icon(
                              pushService.isSubscribed
                                  ? Icons.notifications_off_outlined
                                  : Icons.notifications_active_outlined,
                            ),
                            label: Text(
                              pushService.isSubscribed
                                  ? 'Turn off notifications'
                                  : 'Turn on notifications',
                            ),
                          ),
                        if (statusMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(statusMessage),
                          ),
                      ],
                    ),
                  );
                },
              ),
            Consumer<InstallPromptService>(
              builder: (context, installPromptService, child) {
                if (!installPromptService.isInstallAvailable &&
                    !(me?.authenticated == true &&
                        installPromptService.canOpenInstalledApp)) {
                  return const SizedBox.shrink();
                }
                return _SettingsSection(
                  title: 'App',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (installPromptService.isInstallAvailable)
                        OutlinedButton.icon(
                          onPressed: () {
                            handleInstallRequest(context, installPromptService);
                          },
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: const Text('Install app'),
                        ),
                      if (installPromptService.isInstallAvailable &&
                          me?.authenticated == true &&
                          installPromptService.canOpenInstalledApp)
                        const SizedBox(height: 12),
                      if (me?.authenticated == true &&
                          installPromptService.canOpenInstalledApp) ...[
                        OutlinedButton.icon(
                          onPressed: () =>
                              _openInstalledApp(context, installPromptService),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open installed app'),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Use this after adding Narlun to your home screen to sign into the installed app.',
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            if (me?.authenticated == true)
              _SettingsSection(
                title: 'Account',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _signOut(context),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _deleteAccount(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Text('Delete account'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
