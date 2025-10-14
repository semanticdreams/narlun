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
import 'me_model.dart';
import 'messages_view.dart';
import 'appbar_avatar.dart';

class ConversationsView extends StatefulWidget {
  @override
  _ConversationsState createState() => _ConversationsState();
}

class _ConversationsState extends State<ConversationsView> {
  final HttpService httpService = HttpService();

  final rooms = [];

  final picture_placeholder = 'http://www.gravatar.com/avatar/?d=mp';

  Future update_rooms() async {
    final resp = await httpService.get_rooms();
    setState(() {
      rooms.clear();
      rooms.addAll(resp);
    });
  }

  @override
  void initState() {
    super.initState();
    update_rooms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rooms'),
        actions: [
          AppBarAvatar(),
        ],
      ),
      body: Consumer<MeModel>(builder: (context, me, child) {
        return ListView(children: [
          for (var room in rooms)
            Container(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListTile(
                    leading: CircleAvatar(
                        backgroundImage: NetworkImage(room['is_group'] ||
                                !me.data!['authenticated']
                            ? (room['picture'] ?? picture_placeholder)
                            : room['participants'].singleWhere(
                                (x) => x['id'] != me.data!['id'])['picture']),
                        backgroundColor: Colors.transparent),
                    trailing: Text(
                        timeago.format(DateTime.parse(room['updated_at']))),
                    title: Text(room['is_group'] || !me.data!['authenticated']
                        ? (room['name'] ?? '')
                        : room['participants'].singleWhere(
                            (x) => x['id'] != me.data!['id'])['username']),
                    subtitle: Text(room['last_message'] != null
                        ? room['last_message']['body']
                        : ''),
                    onTap: () async {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  MessagesView(room: room, me: me)));
                    })) // TODO subtitle should be different for group, needs name
        ]);
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add your onPressed code here!
        },
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }
}
