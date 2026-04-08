import 'dart:html' as html;

Future<bool> openExternalLink(String url) async {
  html.window.open(url, '_blank');
  return true;
}
