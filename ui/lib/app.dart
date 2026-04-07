import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_route_state.dart';
import 'app_update_banner.dart';
import 'install_suggestion_banner.dart';
import 'signin_view.dart';
import 'signup_view.dart';
import 'welcome_view.dart';
import 'home_view.dart';
import 'invite_accept_view.dart';
import 'invite_qr_view.dart';
import 'profile_view.dart';
import 'settings_view.dart';
import 'frontend_error_reporter.dart';
import 'me_model.dart';
import 'route_utils.dart';
import 'set_page_title.dart';
import 'websocket.dart';

import 'locator.dart';
import 'dialog_service.dart';
import 'session_watcher.dart';

class MyApp extends StatelessWidget {
  final ThemeData theme;
  final FrontendErrorReporter errorReporter;
  final GlobalKey<NavigatorState> navigatorKey;
  final AppRouteState routeState = AppRouteState();

  MyApp({
    super.key,
    required this.theme,
    required this.errorReporter,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    locator<DialogService>().attachNavigator(navigatorKey);
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, widget) => ChangeNotifierProvider<AppRouteState>.value(
        value: routeState,
        child: AppUpdateBanner(
          child: InstallSuggestionBannerFrame(
            child: SessionWatcher(navigatorKey: navigatorKey, child: widget!),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [
        AppRouteObserver(routeState),
        errorReporter.createNavigatorObserver(),
        LiveViewNavigatorObserver(locator<WebsocketService>()),
      ],
      title: 'narlun | opening',
      theme: theme,
      onGenerateRoute: (RouteSettings settings) {
        Widget? pageView;
        var resolvedSettings = settings;
        final me = Provider.of<MeModel>(context, listen: false).data;
        var resolvedUri = settings.name != null
            ? Uri.parse(settings.name!)
            : null;

        if (resolvedUri != null) {
          final resolvedLocation = resolveStartupLocation(resolvedUri, me);
          if (resolvedLocation != settings.name) {
            resolvedSettings = RouteSettings(
              name: resolvedLocation,
              arguments: settings.arguments,
            );
            resolvedUri = Uri.parse(resolvedLocation);
          }
        }

        if (resolvedUri != null) {
          setPageTitle(resolvedUri, context);
        }
        errorReporter.updateRoute(
          resolvedSettings.name ?? resolvedUri?.toString(),
        );

        if (resolvedUri != null) {
          switch (resolvedUri.path) {
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
              pageView = HomeView(
                initialTabIndex: 1,
                initialRoomIdToOpen: int.tryParse(
                  resolvedUri.queryParameters['open_room'] ?? '',
                ),
              );
              break;
            case '/nearby':
              pageView = const HomeView(initialTabIndex: 0);
              break;
            case '/profile':
              pageView = const ProfileView();
              break;
            case '/settings':
              pageView = const SettingsView();
              break;
            case '/signin':
              pageView = const SigninView();
              break;
            case '/invite':
              pageView = InviteQrView(
                roomId: int.tryParse(
                  resolvedUri.queryParameters['room_id'] ?? '',
                ),
                backToRoute: resolvedUri.queryParameters['back_to'],
                preferPopOnBack: settings.arguments == true,
              );
              break;
          }
          if (pageView == null &&
              resolvedUri.pathSegments.length == 2 &&
              resolvedUri.pathSegments.first == 'invite') {
            pageView = InviteAcceptView(token: resolvedUri.pathSegments[1]);
          }
        }

        if (pageView != null) {
          return MaterialPageRoute(
            settings: resolvedSettings,
            builder: (BuildContext context) => pageView!,
          );
        }

        assert(false, 'Need to implement ${settings.name}');
        return null;
      },
    );
  }
}
