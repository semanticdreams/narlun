import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:json_theme/json_theme.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:chat_bubbles/chat_bubbles.dart';

import 'http.dart';
import 'locator.dart';
import 'dialog_manager.dart';
import 'dialog_service.dart';
import 'me_model.dart';

DialogService _dialogService = locator<DialogService>();

class NearbyUsersView extends StatefulWidget {
  Function(int) on_user_joined;

  NearbyUsersView({required this.on_user_joined});

  @override
  _NearbyUsersState createState() => _NearbyUsersState();
}

class _NearbyUsersState extends State<NearbyUsersView> {
  final HttpService httpService = HttpService();

  final nearby_users = [];

  //final ScrollController controller = ScrollController();

  Future checkin() async {
    final me = Provider.of<MeModel>(context, listen: false);
    if (me.data == null || me.data!['authenticated'] == false) {
      return;
    }
    if (!(await Geolocator.isLocationServiceEnabled())) {
      await _dialogService.showDialog(
          title: 'Error', description: 'Location services aren\'t enabled.');
      return;
    }

    LocationPermission permission;
    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        await _dialogService.showDialog(
            title: 'Error', description: 'Location services denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      await _dialogService.showDialog(
          title: 'Error',
          description: 'Location services are permanently denied.');
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
    final room_id = resp['id'];
    await widget.on_user_joined(room_id);
  }

  @override
  void initState() {
    super.initState();
    checkin();
  }

  @override
  void dispose() {
    //controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
        onRefresh: () async {
          await checkin();
        },
        child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse
            }),
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (var user in nearby_users)
                    Container(
                        //height: 48,
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: ListTile(
                            leading: CircleAvatar(
                                backgroundImage: NetworkImage(user['picture']),
                                backgroundColor: Colors.transparent),
                            title: Text(user['username']),
                            subtitle: Text(user['about_me'] != null
                                ? user['about_me']
                                : ''),
                            trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(user['distance'].toString() + 'm away',
                                      textAlign: TextAlign.right),
                                  SizedBox(height: 4),
                                  Text(
                                      'last seen ' +
                                          timeago.format(DateTime.parse(
                                              user['last_seen'])),
                                      textAlign: TextAlign.right)
                                ]),
                            //trailing: Icon(Icons.more_vert),
                            onTap: () async {
                              await join_user(user);
                            }))
                ])));
  }
}
