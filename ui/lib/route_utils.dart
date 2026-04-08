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

String nearbyRoute() {
  return '/nearby';
}

String roomsRoute({int? openRoom}) {
  return Uri(
    path: '/rooms',
    queryParameters: openRoom == null ? null : {'open_room': '$openRoom'},
  ).toString();
}

String roomsRouteWithOpenRoom(int roomId) {
  return roomsRoute(openRoom: roomId);
}

bool isPrimaryAppShellRoute(Uri uri) {
  return uri.path == '/home' || uri.path == '/nearby' || uri.path == '/rooms';
}

bool shouldShowPersistentInstallSuggestionForRoute(Uri uri) {
  if (uri.path == '/') {
    return false;
  }
  if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'invite') {
    return false;
  }
  return true;
}

String? sanitizeInviteBackToRoute(String? route) {
  if (route == null || route.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(route);
  if (uri == null) {
    return null;
  }
  if (uri.path == '/profile' || isPrimaryAppShellRoute(uri)) {
    return uri.toString();
  }
  return null;
}

String inviteQrRoute({int? roomId}) {
  return inviteQrRouteWithBackTo(roomId: roomId);
}

String inviteQrRouteWithBackTo({int? roomId, String? backTo}) {
  final queryParameters = <String, String>{};
  if (roomId != null) {
    queryParameters['room_id'] = '$roomId';
  }
  if (backTo != null && backTo.isNotEmpty) {
    queryParameters['back_to'] = backTo;
  }
  return Uri(
    path: '/invite',
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
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

String globalInviteUrl() {
  return Uri.base.resolve('/').toString();
}
