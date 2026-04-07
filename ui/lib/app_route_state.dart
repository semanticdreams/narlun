import 'package:flutter/widgets.dart';

class AppRouteState extends ChangeNotifier {
  List<String?> _routeNames = const [];

  String? get routeName => _routeNames.isEmpty ? null : _routeNames.last;

  Uri? get routeUri {
    final name = routeName;
    if (name == null || name.isEmpty) {
      return null;
    }
    return Uri.tryParse(name);
  }

  void updateRouteName(String? routeName) {
    updateRouteStack(routeName == null ? const [] : <String?>[routeName]);
  }

  void updateRouteStack(List<String?> routeNames) {
    if (_listsEqual(_routeNames, routeNames)) {
      return;
    }
    _routeNames = List<String?>.unmodifiable(routeNames);
    notifyListeners();
  }

  bool _listsEqual(List<String?> left, List<String?> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}

class AppRouteObserver extends NavigatorObserver {
  AppRouteObserver(this.routeState);

  final AppRouteState routeState;
  final List<Route<dynamic>> _routeStack = <Route<dynamic>>[];

  bool _isTrackable(Route<dynamic> route) => route.settings.name != null;

  void _syncRouteState() {
    routeState.updateRouteStack(
      _routeStack.map((route) => route.settings.name).toList(growable: false),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isTrackable(route)) {
      super.didPush(route, previousRoute);
      return;
    }
    _routeStack.remove(route);
    _routeStack.add(route);
    _syncRouteState();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isTrackable(route)) {
      super.didPop(route, previousRoute);
      return;
    }
    _routeStack.remove(route);
    _syncRouteState();
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final oldTrackable = oldRoute != null && _isTrackable(oldRoute);
    final newTrackable = newRoute != null && _isTrackable(newRoute);
    if (!oldTrackable && !newTrackable) {
      super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
      return;
    }
    if (oldRoute != null) {
      final index = _routeStack.indexOf(oldRoute);
      if (index != -1) {
        if (!newTrackable) {
          _routeStack.removeAt(index);
        } else {
          _routeStack[index] = newRoute;
        }
      } else if (newTrackable) {
        _routeStack.add(newRoute);
      }
    } else if (newTrackable) {
      _routeStack.remove(newRoute);
      _routeStack.add(newRoute);
    }
    _syncRouteState();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isTrackable(route)) {
      super.didRemove(route, previousRoute);
      return;
    }
    _routeStack.remove(route);
    _syncRouteState();
    super.didRemove(route, previousRoute);
  }
}
