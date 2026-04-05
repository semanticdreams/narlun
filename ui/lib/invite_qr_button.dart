import 'package:flutter/material.dart';

import 'invite_qr_view.dart';
import 'models.dart';
import 'route_utils.dart';

class InviteQrButton extends StatelessWidget {
  final RoomSummary? room;

  const InviteQrButton({super.key, this.room});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key(room == null ? 'global-invite-button' : 'room-invite-button'),
      tooltip: room == null ? 'Invite someone' : 'Invite people to this room',
      icon: const Icon(Icons.qr_code_2_outlined),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            settings: RouteSettings(name: inviteQrRoute(roomId: room?.id)),
            builder: (context) => InviteQrView(room: room),
          ),
        );
      },
    );
  }
}
