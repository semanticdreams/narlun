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
import 'navdrawer.dart';
import 'appbar_avatar.dart';
import 'nearby_users_view.dart';
import 'conversations_view.dart';

class HomeView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: 2,
        child: Builder(builder: (BuildContext context) {
          return Scaffold(
            drawer: NavDrawer(),
            appBar: AppBar(
              title: Text('Narlun'),
              actions: [
                AppBarAvatar(),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.people)),
                  Tab(icon: Icon(Icons.message)),
                  //Tab(icon: Icon(Icons.qr_code_2)),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                NearbyUsersView(on_user_joined: (room_id) {
                  DefaultTabController.of(context)!.animateTo(1);
                }),
                ConversationsView()
              ],
            ),
          );
        }));
  }
}
