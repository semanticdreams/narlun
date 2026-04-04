import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'http.dart';
import 'install_prompt_actions.dart';
import 'install_prompt_service.dart';
import 'me_model.dart';

enum _AccountMenuAction { profile, install, signOut }

class AppBarAvatar extends StatelessWidget {
  const AppBarAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MeModel, InstallPromptService>(
      builder: (context, me, installPromptService, child) {
        return PopupMenuButton<_AccountMenuAction>(
          tooltip: 'Account menu',
          onSelected: (action) async {
            switch (action) {
              case _AccountMenuAction.profile:
                Navigator.pushNamed(context, '/profile');
                break;
              case _AccountMenuAction.install:
                await handleInstallRequest(context, installPromptService);
                break;
              case _AccountMenuAction.signOut:
                final httpService = Provider.of<HttpService>(
                  context,
                  listen: false,
                );
                await httpService.signout();
                if (!context.mounted) {
                  return;
                }
                Provider.of<MeModel>(context, listen: false).reset();
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/',
                  (route) => false,
                );
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _AccountMenuAction.profile,
              child: Text('Profile'),
            ),
            if (installPromptService.isInstallAvailable)
              const PopupMenuItem(
                value: _AccountMenuAction.install,
                child: Text('Install app'),
              ),
            const PopupMenuItem(
              value: _AccountMenuAction.signOut,
              child: Text('Sign out'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox.square(
              dimension: 36,
              child: AvatarImage(picture: me.data?.picture, radius: 18),
            ),
          ),
        );
      },
    );
  }
}
