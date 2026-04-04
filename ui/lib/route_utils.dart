import 'package:flutter/material.dart';

String? nextRouteFromContext(BuildContext context) {
  final routeName = ModalRoute.of(context)?.settings.name;
  if (routeName == null) {
    return null;
  }

  final next = Uri.parse(routeName).queryParameters['next'];
  if (next == null || next.isEmpty) {
    return null;
  }

  return next;
}

String authRouteWithNext(BuildContext context, String path) {
  final next = nextRouteFromContext(context);
  if (next == null) {
    return path;
  }

  return Uri(path: path, queryParameters: {'next': next}).toString();
}
