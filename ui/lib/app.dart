import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:json_theme/json_theme.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:chat_bubbles/chat_bubbles.dart';

import 'signin_view.dart';
import 'signup_view.dart';
import 'welcome_view.dart';
import 'home_view.dart';
import 'profile_view.dart';
import 'http.dart';
import 'me_model.dart';
import 'set_page_title.dart';
import 'conversations_view.dart';

import 'dialog_manager.dart';
import 'dialog_service.dart';

class MyApp extends StatelessWidget {
  final ThemeData theme;

  const MyApp({Key? key, required this.theme}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        builder: (context, widget) => Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (context) => DialogManager(child: widget!))),
        debugShowCheckedModeBanner: false,
        title: 'Narlun',
        theme: theme,
        //theme: ThemeData(
        //  primarySwatch: Colors.purple,
        //),
        //initialRoute: '/',
        //routes: {
        //  '/': (context) => WelcomeView(),
        //  '/signup': (context) => SignupView(),
        //  '/signin': (context) => SigninView(),
        //  '/home': (context) => HomeView(),
        //  '/profile': (context) => ProfileView(),
        //},
        onGenerateRoute: (RouteSettings settings) {
          Widget? page_view;

          final me = Provider.of<MeModel>(context, listen: false).data;

          final uri_data =
              settings.name != null ? Uri.parse(settings.name!) : null;

          if (uri_data != null) {
            setPageTitle(uri_data.path, context);
          }

          // no auth required for these paths
          final unauth_paths = ['/', '/signin', '/signup'];

          if (me == null && uri_data!.path != '/') {
            // show / (loading screen) when auth data unavailable
            final new_query_params = {
              ...uri_data.queryParameters,
              ...{'next': uri_data.path}
            };
            final new_uri = Uri(path: '/', queryParameters: new_query_params);
            final new_settings = RouteSettings(
                name: new_uri.toString(), arguments: settings.arguments);
            return MaterialPageRoute(
                settings: new_settings,
                builder: (BuildContext context) => WelcomeView());
          } else if (me != null &&
              me['authenticated'] == false &&
              !unauth_paths.contains(uri_data!.path)) {
            // unauthenticated user shouldn't be able to visit auth pages
            final new_query_params = {
              ...uri_data.queryParameters,
              ...{'next': uri_data.path}
            };
            final new_uri =
                Uri(path: '/signup', queryParameters: new_query_params);
            final new_settings = RouteSettings(
                name: new_uri.toString(), arguments: settings.arguments);
            return MaterialPageRoute(
                settings: new_settings,
                builder: (BuildContext context) => SignupView());
          } else if (me != null &&
              me['authenticated'] == true &&
              unauth_paths.contains(uri_data!.path)) {
            // authenticated user shouldn't be able to visit unauth pages
            final new_uri = Uri(path: '/rooms');
            final new_settings = RouteSettings(
                name: new_uri.toString(), arguments: settings.arguments);
            return MaterialPageRoute(
                settings: new_settings,
                builder: (BuildContext context) => HomeView());
          }

          if (uri_data != null) {
            switch (uri_data.path) {
              case '/':
                page_view = WelcomeView();
                break;
              case '/signup':
                page_view = SignupView();
                break;
              case '/home':
                page_view = HomeView();
                break;
              case '/rooms':
                page_view = ConversationsView();
                break;
              case '/profile':
                page_view = ProfileView();
                break;
              case '/signin':
                page_view =
                    SigninView(token: uri_data.queryParameters['token']);
                break;
            }
          }

          if (page_view != null) {
            return MaterialPageRoute(
                settings: settings,
                builder: (BuildContext context) => page_view!);
          }

          assert(false, 'Need to implement ${settings.name}');
          return null;
        });
  }
}
