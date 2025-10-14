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

class AppBarAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<MeModel>(builder: (context, me, child) {
      return Container(
          width: 58,
          child: IconButton(
              icon: CircleAvatar(
                backgroundImage: NetworkImage(me.data?['picture'] ??
                    'http://www.gravatar.com/avatar/?d=mp'),
                backgroundColor: Colors.transparent,
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/profile');
              })
          //child: PopupMenuButton(
          //  icon: CircleAvatar(
          //    backgroundImage: NetworkImage(
          //      me.data['picture']
          //    ),
          //    backgroundColor: Colors.transparent,
          //  ),
          //  itemBuilder: (BuildContext context) {
          //    return [
          //      PopupMenuItem<String> (
          //        value: '1',
          //        child: Text('1'),
          //      ),
          //      PopupMenuItem<String> (
          //        value: '2',
          //        child: Text('2'),
          //      ),
          //    ];
          //  },
          //),
          );
    });
  }
}
