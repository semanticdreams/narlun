import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'signin_view.dart';
import 'signup_view.dart';
import 'welcome_view.dart';
import 'home_view.dart';
import 'profile_view.dart';
import 'me_model.dart';
import 'set_page_title.dart';

import 'locator.dart';
import 'dialog_service.dart';
import 'session_watcher.dart';

class MyApp extends StatelessWidget {
  final ThemeData theme;
  final GlobalKey<NavigatorState> navigatorKey;

  MyApp({
    super.key,
    required this.theme,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    locator<DialogService>().attachNavigator(navigatorKey);
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, widget) =>
          SessionWatcher(navigatorKey: navigatorKey, child: widget!),
      debugShowCheckedModeBanner: false,
      title: 'Narlun',
      theme: theme,
      onGenerateRoute: (RouteSettings settings) {
        Widget? pageView;

        final me = Provider.of<MeModel>(context, listen: false).data;
        final uriData = settings.name != null
            ? Uri.parse(settings.name!)
            : null;

        if (uriData != null) {
          setPageTitle(uriData.path, context);
        }

        const unauthPaths = ['/', '/signin', '/signup'];
        final requestedLocation = uriData?.toString();

        if (me == null && uriData!.path != '/') {
          final newUri = Uri(
            path: '/',
            queryParameters: requestedLocation == null
                ? null
                : {'next': requestedLocation},
          );
          return MaterialPageRoute(
            settings: RouteSettings(
              name: newUri.toString(),
              arguments: settings.arguments,
            ),
            builder: (BuildContext context) => const WelcomeView(),
          );
        } else if (me != null &&
            me.authenticated == false &&
            !unauthPaths.contains(uriData!.path)) {
          final newUri = Uri(
            path: '/signup',
            queryParameters: requestedLocation == null
                ? null
                : {'next': requestedLocation},
          );
          return MaterialPageRoute(
            settings: RouteSettings(
              name: newUri.toString(),
              arguments: settings.arguments,
            ),
            builder: (BuildContext context) => const SignupView(),
          );
        } else if (me != null &&
            me.authenticated == true &&
            unauthPaths.contains(uriData!.path)) {
          return MaterialPageRoute(
            settings: RouteSettings(
              name: '/home',
              arguments: settings.arguments,
            ),
            builder: (BuildContext context) => const HomeView(),
          );
        }

        if (uriData != null) {
          switch (uriData.path) {
            case '/':
              pageView = const WelcomeView();
              break;
            case '/signup':
              pageView = const SignupView();
              break;
            case '/home':
              pageView = const HomeView();
              break;
            case '/rooms':
              pageView = const HomeView(initialTabIndex: 1);
              break;
            case '/nearby':
              pageView = const HomeView(initialTabIndex: 0);
              break;
            case '/profile':
              pageView = const ProfileView();
              break;
            case '/signin':
              pageView = const SigninView();
              break;
          }
        }

        if (pageView != null) {
          return MaterialPageRoute(
            settings: settings,
            builder: (BuildContext context) => pageView!,
          );
        }

        assert(false, 'Need to implement ${settings.name}');
        return null;
      },
    );
  }
}
