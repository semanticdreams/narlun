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

import 'http.dart';
import 'me_model.dart';

class SigninView extends StatefulWidget {
  final String? token;

  const SigninView({Key? key, this.token}) : super(key: key);

  @override
  SigninState createState() {
    return SigninState();
  }
}

class SigninState extends State<SigninView> {
  final GlobalKey<FormState> _formKey = new GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final emailController = TextEditingController();

  final HttpService httpService = HttpService();

  int _selectedTab = 0;

  void submit(context) async {
    var me;
    if (_selectedTab == 0) {
      me = await httpService.signin(
          email: emailController.text, method: 'email');
      if (me['email_sent']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signin email sent')),
        );
      } else {
        assert(false);
      }
    } else {
      try {
        me = await httpService.signin(
            username: usernameController.text,
            password: passwordController.text,
            method: 'password');
        Provider.of<MeModel>(context, listen: false).set_data(me);
        Navigator.pushNamed(context, '/rooms');
      } on InvalidUsage catch (e) {
        // TODO select all on error, this might need to focus first
        usernameController.selection = TextSelection(
            baseOffset: 0, extentOffset: usernameController.value.text.length);
      }
    }
  }

  void signin_with_token() async {
    var me = await httpService.signin(token: widget.token, method: 'token');
    Provider.of<MeModel>(context, listen: false).set_data(me);
    Navigator.pushNamed(context, '/rooms');
  }

  @override
  void initState() {
    super.initState();
    if (widget.token != null) {
      signin_with_token();
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
        data: Theme.of(context),
        child: DefaultTabController(
            length: 2,
            child: Builder(builder: (BuildContext context) {
              return Scaffold(
                  backgroundColor: Colors.purple[100],
                  body: Container(
                      padding: new EdgeInsets.all(20.0),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Narlun',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 50,
                                  color: Colors.purple),
                            ),
                            Text('Sign in to your account.',
                                textAlign: TextAlign.center),
                            Container(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  TabBar(
                                      labelColor: Colors.purple,
                                      indicatorColor: Colors.purple,
                                      tabs: [
                                        Tab(icon: Icon(Icons.email)),
                                        Tab(icon: Icon(Icons.password)),
                                      ],
                                      onTap: (index) {
                                        setState(() {
                                          _selectedTab = index;
                                        });
                                      }),
                                  Builder(builder: (_) {
                                    if (_selectedTab == 0) {
                                      return Container(
                                          padding: new EdgeInsets.symmetric(
                                              vertical: 10.0),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: <Widget>[
                                                new TextField(
                                                  autofocus: true,
                                                  decoration:
                                                      new InputDecoration(
                                                    labelText: 'Email',
                                                  ),
                                                  controller: emailController,
                                                  onSubmitted: (v) =>
                                                      this.submit(context),
                                                ),
                                                new Container(
                                                  //                width: screenSize.width,
                                                  child: new ElevatedButton(
                                                    child: new Text(
                                                      'Send signin email',
                                                      style: new TextStyle(
                                                          color: Colors
                                                              .purple[100]),
                                                    ),
                                                    onPressed: () =>
                                                        this.submit(context),
                                                    //color: Colors.white,
                                                  ),
                                                  margin: new EdgeInsets.only(
                                                      top: 20.0),
                                                )
                                              ]));
                                    } else {
                                      return Container(
                                          padding: new EdgeInsets.symmetric(
                                              vertical: 10.0),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                new TextField(
                                                  autofocus: true,
                                                  decoration:
                                                      new InputDecoration(
                                                    //hintText: 'Choose any name',
                                                    labelText: 'Username',
                                                  ),
                                                  controller:
                                                      usernameController,
                                                  onSubmitted: (v) =>
                                                      this.submit(context),
                                                  //color: Colors.white,
                                                ),
                                                new TextField(
                                                  decoration:
                                                      new InputDecoration(
                                                    //hintText: 'Choose any name',
                                                    labelText: 'Password',
                                                  ),
                                                  obscureText: true,
                                                  enableSuggestions: false,
                                                  autocorrect: false,
                                                  controller:
                                                      passwordController,
                                                  onSubmitted: (v) =>
                                                      this.submit(context),
                                                  //color: Colors.white,
                                                ),
                                                new Container(
                                                  //                width: screenSize.width,
                                                  child: new ElevatedButton(
                                                    child: new Text(
                                                      'Sign In',
                                                      style: new TextStyle(
                                                          color: Colors
                                                              .purple[100]),
                                                    ),
                                                    onPressed: () =>
                                                        this.submit(context),
                                                    //color: Colors.white,
                                                  ),
                                                  margin: new EdgeInsets.only(
                                                      top: 20.0),
                                                )
                                              ]));
                                    }
                                  }),
                                ])),
                            Text('', textAlign: TextAlign.center),
                            TextButton(
                                child: Text(
                                    'Don\'t have an account? Click to sign up.'),
                                onPressed: () {
                                  Navigator.pushNamed(context, '/signup');
                                }),
                          ])));
            })));
  }
}
