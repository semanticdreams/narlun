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
import 'profile_form.dart';
import 'http.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';
import 'me_model.dart';

class ProfileView extends StatelessWidget {
  final HttpService httpService = HttpService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Profile'),
          actions: [],
          leading: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context);
                //Navigator.of(context).pushReplacementNamed('/rooms');
              }),
        ),
        body: Consumer<MeModel>(builder: (context, me, child) {
          return Container(
              padding: EdgeInsets.all(20),
              child: Column(children: [
                Stack(children: [
                  Container(
                    alignment: Alignment.center,
                    child: CircleAvatar(
                        backgroundImage: NetworkImage(me.data?['picture'] ??
                            'http://www.gravatar.com/avatar/?d=mp'),
                        backgroundColor: Colors.transparent,
                        radius: 64),
                  ),
                  Container(
                      alignment: Alignment.topRight,
                      child: TextButton(
                          child: Text('Upload picture'),
                          onPressed: () async {
                            FilePickerResult? result =
                                await FilePicker.platform.pickFiles();
                            if (result != null) {
                              Uint8List file = result.files.single.bytes!;
                              final data = await httpService
                                  .upload_profile_picture(file);
                              Provider.of<MeModel>(context, listen: false)
                                  .set_profile_picture(data['picture']);

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Profile picture saved')),
                              );
                            }
                          })),
                ]),
                ProfileForm(data: me.data)
              ]));
        }));
  }
}
