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

class ProfileForm extends StatefulWidget {
  final data;

  const ProfileForm({Key? key, this.data}) : super(key: key);

  @override
  ProfileFormState createState() {
    return ProfileFormState();
  }
}

class ProfileFormState extends State<ProfileForm> {
  final HttpService httpService = HttpService();

  final _formKey = GlobalKey<FormState>();

  String? username;
  String? email;
  String? password;
  String? phone;
  String? about_me;

  final password_placeholder = '********';

  ProfileFormState();

  @override
  Widget build(BuildContext context) {
    return Form(
        key: _formKey,
        child: Column(children: [
          TextFormField(
              initialValue: widget.data['username'],
              onSaved: (String? v) {
                username = v;
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Username can\'t be empty';
                }
              },
              decoration: new InputDecoration(
                hintText: 'Enter a username',
                labelText: 'Username',
              )),
          TextFormField(
              initialValue: widget.data['email'] ?? '',
              onSaved: (String? v) {
                email = v;
              },
              decoration: new InputDecoration(
                hintText: 'Enter an email',
                labelText: 'Email',
              )),
          TextFormField(
              initialValue:
                  widget.data['has_password'] ? password_placeholder : null,
              onSaved: (String? v) {
                password = v;
              },
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: new InputDecoration(
                hintText: 'Enter a password',
                labelText: 'Password',
              )),
          TextFormField(
              initialValue: widget.data['phone'] ?? '',
              onSaved: (String? v) {
                phone = v;
              },
              decoration: new InputDecoration(
                hintText: 'Set a phone number for quick sharing in messages',
                labelText: 'Phone',
              )),
          TextFormField(
              initialValue: widget.data['about_me'] ?? '',
              //initialValue: jsonEncode(widget.data),
              onSaved: (String? v) {
                about_me = v;
              },
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: new InputDecoration(
                hintText: 'Say something about yourself! Use # to create tags.',
                labelText: 'About me',
              )),
          SizedBox(height: 10),
          Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                child: const Text('Save'),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();

                    var data = {
                      'username': username,
                      'email': email,
                      'about_me': about_me,
                      'phone': phone
                    };
                    if (password != password_placeholder) {
                      data['password'] = password;
                    }

                    final me = await httpService.update_profile(data);
                    Provider.of<MeModel>(context, listen: false).set_data(me);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile saved')),
                    );
                  }
                },
              ))
        ]));
  }
}
