// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void setBrowserPageTitle(String title) {
  html.document.title = title;
}
