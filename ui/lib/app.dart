import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'signin_view.dart';
import 'signup_view.dart';
import 'welcome_view.dart';
import 'home_view.dart';
import 'profile_view.dart';
import 'me_model.dart';
import 'set_page_title.dart';
import 'conversations_view.dart';

import 'dialog_manager.dart';
import 'session_watcher.dart';

class MyApp extends StatelessWidget {
  final ThemeData theme;
  final GlobalKey<NavigatorState> navigatorKey;

  MyApp({
    Key? key,
    required this.theme,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, widget) => DialogManager(
        child: SessionWatcher(navigatorKey: navigatorKey, child: widget!),
      ),
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

        if (me == null && uriData!.path != '/') {
          final newUri = Uri(
            path: '/',
            queryParameters: {...uriData.queryParameters, 'next': uriData.path},
          );
          return MaterialPageRoute(
            settings: RouteSettings(
              name: newUri.toString(),
              arguments: settings.arguments,
            ),
            builder: (BuildContext context) => WelcomeView(),
          );
        } else if (me != null &&
            me['authenticated'] == false &&
            !unauthPaths.contains(uriData!.path)) {
          final newUri = Uri(
            path: '/signup',
            queryParameters: {...uriData.queryParameters, 'next': uriData.path},
          );
          return MaterialPageRoute(
            settings: RouteSettings(
              name: newUri.toString(),
              arguments: settings.arguments,
            ),
            builder: (BuildContext context) => SignupView(),
          );
        } else if (me != null &&
            me['authenticated'] == true &&
            unauthPaths.contains(uriData!.path)) {
          return MaterialPageRoute(
            settings: RouteSettings(
              name: '/rooms',
              arguments: settings.arguments,
            ),
            builder: (BuildContext context) => HomeView(),
          );
        }

        if (uriData != null) {
          switch (uriData.path) {
            case '/':
              pageView = WelcomeView();
              break;
            case '/signup':
              pageView = SignupView();
              break;
            case '/home':
              pageView = HomeView();
              break;
            case '/rooms':
              pageView = ConversationsView();
              break;
            case '/profile':
              pageView = ProfileView();
              break;
            case '/signin':
              pageView = SigninView();
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
