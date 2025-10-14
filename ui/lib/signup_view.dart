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
import 'package:username_gen/username_gen.dart';

class SignupView extends StatefulWidget {
  const SignupView({Key? key}) : super(key: key);

  @override
  SignupViewState createState() {
    return SignupViewState();
  }
}

class SignupViewState extends State<SignupView> {
  final GlobalKey<FormState> _formKey = new GlobalKey<FormState>();
  final usernameController = TextEditingController();

  final HttpService httpService = HttpService();

  bool usernameReadOnly = false;

  void submit(context) async {
    try {
      final me = await httpService.signup(usernameController.text);
      Provider.of<MeModel>(context, listen: false).set_data(me);
      Navigator.pushNamed(context, '/rooms');
    } on InvalidUsage catch (e) {
      // TODO select all on error, this might need to focus first
      usernameController.selection = TextSelection(
          baseOffset: 0, extentOffset: usernameController.value.text.length);
    }
  }

  @override
  void dispose() {
    super.dispose();
    usernameController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
        data: Theme.of(context),
        child: Scaffold(
            backgroundColor: Colors.purple[100],
            body: Container(
                padding: new EdgeInsets.all(20.0),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Narlun',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 50,
                            color: Colors.purple),
                      ),
                      Text(
                          'Text random people near you.\n\nTo begin, enter a username and click on Sign Up.',
                          textAlign: TextAlign.center),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          new TextField(
                            autofocus: true,
                            readOnly: usernameReadOnly,
                            onTap: () {
                              setState(() {
                                usernameReadOnly = false;
                              });
                            },
                            decoration: new InputDecoration(
                                //hintText: 'Choose any name',
                                labelText: 'Username',
                                suffixIcon: IconButton(
                                    icon: Icon(Icons.shuffle_on_outlined),
                                    tooltip: 'Generate random username',
                                    onPressed: () {
                                      setState(() {
                                        usernameReadOnly = true;
                                      });
                                      usernameController.text =
                                          UsernameGen().generate();
                                    })),
                            controller: usernameController,
                            onSubmitted: (v) => this.submit(context),
                            //color: Colors.white,
                          ),
                          new Container(
                            //                width: screenSize.width,
                            child: new ElevatedButton(
                              child: new Text(
                                'Sign Up',
                                style: new TextStyle(color: Colors.purple[100]),
                              ),
                              onPressed: () => this.submit(context),
                              //color: Colors.white,
                            ),
                            margin: new EdgeInsets.only(top: 20.0),
                          )
                        ],
                      ),
                      Text(
                          'To make your account permanent, set an email or password in your profile settings.',
                          textAlign: TextAlign.center),
                      TextButton(
                          child: Text(
                              'Already have an account? Click to sign in.'),
                          onPressed: () {
                            Navigator.pushNamed(context, '/signin');
                          }),
                    ]))));
  }
}
