import 'package:flutter/widgets.dart';

class AppRouteState extends ChangeNotifier {
  String? _routeName;

  String? get routeName => _routeName;

  Uri? get routeUri {
    final name = _routeName;
    if (name == null || name.isEmpty) {
      return null;
    }
    return Uri.tryParse(name);
  }

  void updateRouteName(String? routeName) {
    if (_routeName == routeName) {
      return;
    }
    _routeName = routeName;
    notifyListeners();
  }
}

class AppRouteObserver extends NavigatorObserver {
  AppRouteObserver(this.routeState);

  final AppRouteState routeState;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routeState.updateRouteName(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routeState.updateRouteName(previousRoute?.settings.name);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    routeState.updateRouteName(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
