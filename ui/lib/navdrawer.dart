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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'http.dart';
import 'main.dart';
import 'me_model.dart';

class NavDrawer extends StatelessWidget {
  final HttpService httpService = HttpService();

  @override
  Widget build(BuildContext context) {
    return Drawer(
        child: ListView(padding: EdgeInsets.zero, children: <Widget>[
      //DrawerHeader(
      //  child: Text(
      //    'narlun',
      //    style: TextStyle(color: Colors.white, fontSize: 25),
      //  ),
      //  /decoration: BoxDecoration(
      //  /  color: Colors.green,
      //  /  image: DecorationImage(
      //  /    fit: BoxFit.fill,
      //  /    image: AssetImage('assets/cover.jpg'),
      //  /  ),
      //  /),
      //),
      //ListTile(
      //  leading: Icon(Icons.home),
      //  title: Text('Home'),
      //  onTap: () {
      //    Navigator.pop(context);
      //    Navigator.pushNamed(context, '/home');
      //  },
      //),
      ListTile(
        leading: Icon(Icons.groups),
        title: Text('Rooms'),
        onTap: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, '/rooms');
        },
      ),
      ListTile(
        leading: Icon(Icons.input),
        title: Text('Sign Out'),
        onTap: () async {
          await httpService.signout();
          Provider.of<MeModel>(context, listen: false).reset();

          Navigator.pop(context);
          //Navigator.of(context)
          //    .pushNamedAndRemoveUntil('/', ModalRoute.withName('/'));
          Navigator.pushReplacementNamed(context, '/');
          //Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    ]));
  }
}
