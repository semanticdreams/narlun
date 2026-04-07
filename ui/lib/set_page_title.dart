import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'set_page_title_default.dart'
    if (dart.library.html) 'set_page_title_browser.dart'
    as browser_title;

String describePageTitle(Uri uri) {
  String section;
  switch (uri.path) {
    case '/':
      section = 'opening';
      break;
    case '/home':
      section = 'home';
      break;
    case '/nearby':
      section = 'nearby';
      break;
    case '/rooms':
      section = uri.queryParameters.containsKey('open_room') ? 'room' : 'rooms';
      break;
    case '/profile':
      section = 'profile';
      break;
    case '/settings':
      section = 'settings';
      break;
    case '/signin':
      section = 'sign in';
      break;
    case '/signup':
      section = 'sign up';
      break;
    case '/invite':
      section = 'invite';
      break;
    default:
      section =
          uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'invite'
          ? 'invite'
          : 'home';
      break;
  }
  return 'narlun | $section';
}

void setPageTitle(Uri uri, BuildContext context) {
  final title = describePageTitle(uri);
  browser_title.setBrowserPageTitle(title);
  SystemChrome.setApplicationSwitcherDescription(
    ApplicationSwitcherDescription(
      label: title,
      primaryColor: Theme.of(context).primaryColor.toARGB32(),
    ),
  );
}
