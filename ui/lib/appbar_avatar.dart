import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'feedback_dialog.dart';
import 'me_model.dart';
import 'route_utils.dart';

enum _AccountMenuAction { profile, settings, feedback }

class AppBarAvatar extends StatelessWidget {
  const AppBarAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MeModel>(
      builder: (context, me, child) {
        final currentPath = currentRouteUri(context)?.path;
        return PopupMenuButton<_AccountMenuAction>(
          tooltip: 'Account menu',
          onSelected: (action) async {
            switch (action) {
              case _AccountMenuAction.profile:
                Navigator.pushNamed(context, '/profile');
                break;
              case _AccountMenuAction.settings:
                Navigator.pushNamed(context, '/settings');
                break;
              case _AccountMenuAction.feedback:
                final submitted = await showFeedbackDialog(
                  context,
                  source: 'account_menu',
                  details: const {'surface': 'account_menu'},
                );
                if (!context.mounted || !submitted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feedback sent. Thank you.')),
                );
                break;
            }
          },
          itemBuilder: (context) => [
            if (currentPath != '/profile')
              const PopupMenuItem(
                value: _AccountMenuAction.profile,
                child: Text('Profile'),
              ),
            if (currentPath != '/settings')
              const PopupMenuItem(
                value: _AccountMenuAction.settings,
                child: Text('Settings'),
              ),
            const PopupMenuItem(
              value: _AccountMenuAction.feedback,
              child: Text('Send feedback'),
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
