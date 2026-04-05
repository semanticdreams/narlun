import 'package:flutter/material.dart';

import 'models.dart';

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

String? _resolveStartupRedirectOnce(Uri uri, SessionUser? me) {
  final requestedLocation = uri.toString();
  final next = uri.queryParameters['next'];
  const unauthPaths = {'/', '/signin', '/signup'};

  if (me == null) {
    if (uri.path == '/') {
      return null;
    }
    return Uri(
      path: '/',
      queryParameters: {'next': requestedLocation},
    ).toString();
  }

  if (me.authenticated) {
    if (uri.path == '/') {
      return next ?? '/home';
    }
    if (unauthPaths.contains(uri.path)) {
      return '/home';
    }
    return null;
  }

  if (uri.path == '/') {
    return Uri(
      path: '/signup',
      queryParameters: next == null ? null : {'next': next},
    ).toString();
  }

  if (!unauthPaths.contains(uri.path)) {
    return Uri(
      path: '/signup',
      queryParameters: {'next': requestedLocation},
    ).toString();
  }

  return null;
}

String resolveStartupLocation(Uri uri, SessionUser? me) {
  var resolved = uri;
  for (var i = 0; i < 5; i += 1) {
    final redirect = _resolveStartupRedirectOnce(resolved, me);
    if (redirect == null || redirect == resolved.toString()) {
      return resolved.toString();
    }
    resolved = Uri.parse(redirect);
  }
  return resolved.toString();
}

String authRouteWithNext(BuildContext context, String path) {
  final next = nextRouteFromContext(context);
  if (next == null) {
    return path;
  }

  return Uri(path: path, queryParameters: {'next': next}).toString();
}
