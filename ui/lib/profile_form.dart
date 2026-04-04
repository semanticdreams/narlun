import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';


class ProfileForm extends StatefulWidget {
  final dynamic data;

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
  String? password;
  String? phone;
  String? aboutMe;

  static const passwordPlaceholder = '********';

  @override
  Widget build(BuildContext context) {
    final hasPassword = widget.data['has_password'] == true;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            initialValue: widget.data['username'],
            onSaved: (String? value) {
              username = value;
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Username can\'t be empty';
              }
              return null;
            },
            decoration: const InputDecoration(
              hintText: 'Enter a username',
              labelText: 'Username',
            ),
          ),
          TextFormField(
            initialValue: hasPassword ? passwordPlaceholder : null,
            onSaved: (String? value) {
              password = value;
            },
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: hasPassword ? 'Change your password' : 'Set a password',
              labelText: hasPassword ? 'Password' : 'Make account permanent',
            ),
          ),
          TextFormField(
            initialValue: widget.data['phone'] ?? '',
            onSaved: (String? value) {
              phone = value;
            },
            decoration: const InputDecoration(
              hintText: 'Set a phone number for quick sharing in messages',
              labelText: 'Phone',
            ),
          ),
          TextFormField(
            initialValue: widget.data['about_me'] ?? '',
            onSaved: (String? value) {
              aboutMe = value;
            },
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Say something about yourself! Use # to create tags.',
              labelText: 'About me',
            ),
          ),
          const SizedBox(height: 10),
          if (!hasPassword)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Without a password this account will be deleted on sign out.',
                textAlign: TextAlign.center,
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              child: const Text('Save'),
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  _formKey.currentState!.save();

                  final data = {
                    'username': username,
                    'about_me': aboutMe,
                    'phone': phone,
                  };
                  if (password != null && password != passwordPlaceholder) {
                    data['password'] = password;
                  }

                  final me = await httpService.update_profile(data);
                  Provider.of<MeModel>(context, listen: false).set_data(me);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile saved')),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
