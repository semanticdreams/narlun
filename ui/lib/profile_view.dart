import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'http.dart';
import 'image_picker.dart';
import 'install_prompt_actions.dart';
import 'install_prompt_service.dart';
import 'me_model.dart';
import 'models.dart';
import 'profile_form.dart';
import 'push_notifications_service.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

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

    if (confirmed == true) {
      await httpService.delete_account();
      if (!context.mounted) {
        return;
      }
      Provider.of<MeModel>(context, listen: false).reset();
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Consumer<MeModel>(
        builder: (context, me, child) {
          final SessionUser? currentUser = me.data;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      child: AvatarImage(
                        picture: currentUser?.picture,
                        radius: 64,
                      ),
                    ),
                    Container(
                      alignment: Alignment.topRight,
                      child: TextButton(
                        child: const Text('Upload picture'),
                        onPressed: () async {
                          final httpService = Provider.of<HttpService>(
                            context,
                            listen: false,
                          );
                          final file = await pickImageBytes();
                          if (file != null) {
                            final picture = await httpService
                                .upload_profile_picture(file);
                            if (!context.mounted) {
                              return;
                            }
                            Provider.of<MeModel>(
                              context,
                              listen: false,
                            ).setProfilePicture(picture);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile picture saved'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (currentUser != null) ProfileForm(data: currentUser),
                Consumer<PushNotificationsService>(
                  builder: (context, pushService, child) {
                    if (currentUser?.authenticated != true ||
                        !pushService.isSupported) {
                      return const SizedBox.shrink();
                    }

                    final statusMessage = pushService.statusMessage;
                    final canShowAction =
                        pushService.isConfigured || pushService.isSubscribed;
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (canShowAction)
                              OutlinedButton.icon(
                                onPressed: pushService.isBusy
                                    ? null
                                    : () async {
                                        if (pushService.isSubscribed) {
                                          await pushService
                                              .disableNotifications();
                                        } else {
                                          await pushService
                                              .enableNotifications();
                                        }
                                      },
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
                      ),
                    );
                  },
                ),
                Consumer<InstallPromptService>(
                  builder: (context, installPromptService, child) {
                    if (!installPromptService.isInstallAvailable) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            handleInstallRequest(context, installPromptService);
                          },
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: const Text('Install app'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _deleteAccount(context),
                    child: const Text('Delete account'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
