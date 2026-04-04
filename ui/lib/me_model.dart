import 'package:flutter/material.dart';

class MeModel extends ChangeNotifier {
  Map<String, dynamic>? data;

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
