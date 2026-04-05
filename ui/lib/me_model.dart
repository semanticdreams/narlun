import 'package:flutter/material.dart';

import 'models.dart';

class MeModel extends ChangeNotifier {
  SessionUser? data;

  MeModel({this.data});

  void setData(SessionUser d) {
    data = d;
    notifyListeners();
  }

  void setProfilePicture(String picture) {
    data = data?.copyWith(picture: picture);
    notifyListeners();
  }

  void reset() {
    data = SessionUser.unauthenticated();
    notifyListeners();
  }
}
