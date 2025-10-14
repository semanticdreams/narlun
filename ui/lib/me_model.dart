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

class MeModel extends ChangeNotifier {
  //Map<String, dynamic> data = {'authenticated': false};
  Map<String, dynamic>? data = null;

  void set_data(d) {
    data = d;
    notifyListeners();
  }

  void set_profile_picture(String picture) {
    data!['picture'] = picture;
    notifyListeners();
  }

  void reset() {
    data = {'authenticated': false};
    notifyListeners();
  }
}
