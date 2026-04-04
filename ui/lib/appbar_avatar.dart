import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'me_model.dart';

class AppBarAvatar extends StatelessWidget {
  const AppBarAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MeModel>(
      builder: (context, me, child) {
        return SizedBox(
          width: 58,
          child: IconButton(
            tooltip: 'Profile',
            icon: AvatarImage(picture: me.data?.picture),
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
          ),
        );
      },
    );
  }
}
