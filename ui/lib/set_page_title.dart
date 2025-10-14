import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

void setPageTitle(String title, context) {
  SystemChrome.setApplicationSwitcherDescription(ApplicationSwitcherDescription(
    label: title,
    primaryColor: Theme.of(context).primaryColor.value, // This line is required
  ));
}
