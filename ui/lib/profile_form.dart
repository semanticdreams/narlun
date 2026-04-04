import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';
import 'models.dart';

const maxStatusLength = 80;

class ProfileForm extends StatefulWidget {
  final SessionUser data;

  const ProfileForm({Key? key, required this.data}) : super(key: key);

  @override
  ProfileFormState createState() {
    return ProfileFormState();
  }
}

class ProfileFormState extends State<ProfileForm> {
  late final HttpService httpService;
  final _formKey = GlobalKey<FormState>();

  String? username;
  String? password;
  String? phone;
  String? status;

  static const passwordPlaceholder = '********';

  @override
  void initState() {
    super.initState();
    httpService = Provider.of<HttpService>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = widget.data.hasPassword;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            initialValue: widget.data.username,
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
            initialValue: widget.data.status ?? '',
            onSaved: (String? value) {
              status = value?.trim();
            },
            maxLines: 1,
            maxLength: maxStatusLength,
            decoration: const InputDecoration(
              hintText: 'Set a short status people see nearby',
              labelText: 'Status',
            ),
          ),
          TextFormField(
            initialValue: widget.data.phone ?? '',
            onSaved: (String? value) {
              phone = value;
            },
            decoration: const InputDecoration(
              hintText: 'Set a phone number for quick sharing in messages',
              labelText: 'Phone',
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
                    'status': status,
                    'phone': phone,
                  };
                  if (password != null && password != passwordPlaceholder) {
                    data['password'] = password;
                  }

                  final me = await httpService.update_profile(data);
                  if (!mounted) {
                    return;
                  }
                  Provider.of<MeModel>(context, listen: false).setData(me);

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
