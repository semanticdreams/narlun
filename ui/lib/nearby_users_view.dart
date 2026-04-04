import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:geolocator/geolocator.dart';

import 'avatar_image.dart';
import 'http.dart';
import 'locator.dart';
import 'dialog_service.dart';
import 'me_model.dart';

final DialogService _dialogService = locator<DialogService>();

class NearbyUsersView extends StatefulWidget {
  const NearbyUsersView({super.key, required this.onUserJoined});

  final FutureOr<void> Function(int) onUserJoined;

  @override
  _NearbyUsersState createState() => _NearbyUsersState();
}

class _NearbyUsersState extends State<NearbyUsersView> {
  final HttpService httpService = HttpService();

  final nearby_users = [];

  Future checkin() async {
    final me = Provider.of<MeModel>(context, listen: false);
    if (me.data == null || me.data!['authenticated'] == false) {
      return;
    }
    if (!(await Geolocator.isLocationServiceEnabled())) {
      await _dialogService.showDialog(
        title: 'Error',
        description: 'Location services aren\'t enabled.',
      );
      return;
    }

    LocationPermission permission;
    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        await _dialogService.showDialog(
          title: 'Error',
          description: 'Location services denied.',
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      await _dialogService.showDialog(
        title: 'Error',
        description: 'Location services are permanently denied.',
      );
      return;
    }

    final loc = await Geolocator.getCurrentPosition();
    final resp = await httpService.checkin(loc.latitude, loc.longitude);

    setState(() {
      nearby_users.clear();
      nearby_users.addAll(resp['nearby_users']);
    });
  }

  Future join_user(user) async {
    final resp = await httpService.join_user(user['id']);
    final roomId = resp['id'];
    await Future.sync(() => widget.onUserJoined(roomId));
  }

  @override
  void initState() {
    super.initState();
    checkin();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await checkin();
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (var user in nearby_users)
              Container(
                //height: 48,
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListTile(
                  leading: AvatarImage(picture: user['picture']),
                  title: Text(user['username']),
                  subtitle: Text(
                    user['about_me'] != null ? user['about_me'] : '',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${user['distance']}m away',
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'last seen ${timeago.format(DateTime.parse(user['last_seen']))}',
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                  onTap: () async {
                    await join_user(user);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
