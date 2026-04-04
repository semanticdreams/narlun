import 'package:flutter/material.dart';

Uri? currentRouteUri(BuildContext context) {
  final routeName = ModalRoute.of(context)?.settings.name;
  if (routeName == null) {
    return null;
  }
  return Uri.parse(routeName);
}

String? nextRouteFromContext(BuildContext context) {
  final uri = currentRouteUri(context);
  if (uri == null) {
    return null;
  }
  final next = uri.queryParameters['next'];
  if (next == null || next.isEmpty) {
    return null;
  }

  return next;
}

int? roomToOpenFromContext(BuildContext context) {
  final uri = currentRouteUri(context);
  final openRoom = uri?.queryParameters['open_room'];
  if (openRoom == null || openRoom.isEmpty) {
    return null;
  }
  return int.tryParse(openRoom);
}

String roomsRouteWithOpenRoom(int roomId) {
  return Uri(
    path: '/rooms',
    queryParameters: {'open_room': '$roomId'},
  ).toString();
}

String invitePathForToken(String token) {
  return '/invite/$token';
}

String inviteUrlForToken(String token) {
  return Uri.base.resolve(invitePathForToken(token)).toString();
}

String authRouteWithNext(BuildContext context, String path) {
  final next = nextRouteFromContext(context);
  if (next == null) {
    return path;
  }

  return Uri(path: path, queryParameters: {'next': next}).toString();
}
