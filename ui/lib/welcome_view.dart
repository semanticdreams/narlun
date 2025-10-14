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

class WelcomeView extends StatefulWidget {
  @override
  _WelcomeState createState() => _WelcomeState();
}

class _WelcomeState extends State<WelcomeView> {
  final HttpService httpService = HttpService();

  void init_me() async {
    final me = await httpService.fetch_me();
    Provider.of<MeModel>(context, listen: false).set_data(me);
    if (ModalRoute.of(context)?.isCurrent == true) {
      // TODO this causes silent error
      final name = ModalRoute.of(context)!.settings.name;
      final uri_data = Uri.parse(name!);
      final next = uri_data.queryParameters['next'];

      //Navigator.of(context).popUntil(ModalRoute.withName('/'));
      Navigator.of(context).popUntil((route) => route.isFirst);

      if (next != null) {
        Navigator.pushReplacementNamed(context, next);
      } else {
        if (me['authenticated']) {
          Navigator.pushReplacementNamed(context, '/rooms');
        } else {
          Navigator.pushReplacementNamed(context, '/signup');
        }
      }
    }
  }

  @override
  void initState() {
    init_me(); // TODO this is still called multiple times
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.purple,
        body: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              Text(
                'Narlun',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 50,
                    color: Colors.white),
              ),
              SizedBox(height: 30),
              CircularProgressIndicator(color: Colors.white)
            ])));
  }
}
