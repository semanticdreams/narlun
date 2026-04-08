import 'package:flutter/material.dart';

import 'models.dart';
import 'route_utils.dart';

class InviteQrButton extends StatelessWidget {
  final RoomSummary? room;
  final String? backToRoute;

  const InviteQrButton({super.key, this.room, this.backToRoute});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key(room == null ? 'global-invite-button' : 'room-invite-button'),
      tooltip: room == null ? 'Invite to Narlun' : 'Invite people to this room',
      icon: const Icon(Icons.qr_code_2_outlined),
      onPressed: () {
        Navigator.of(context).pushNamed(
          inviteQrRouteWithBackTo(
            roomId: room?.id,
            backTo: backToRoute ?? currentRouteUri(context)?.toString(),
          ),
          arguments: true,
        );
      },
    );
  }
}
