import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dialog_service.dart';
import 'http.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'passphrase_generator.dart';
import 'session_actions.dart';

const maxStatusLength = 80;

class ProfileForm extends StatefulWidget {
  final SessionUser data;

  const ProfileForm({super.key, required this.data});

  @override
  ProfileFormState createState() {
    return ProfileFormState();
  }
}

class ProfileFormState extends State<ProfileForm> {
  late final HttpService httpService;
  final _formKey = GlobalKey<FormState>();
  final passwordController = TextEditingController();

  String? username;
  String? status;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();
    httpService = Provider.of<HttpService>(context, listen: false);
  }

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  void _fillGeneratedPassphrase() {
    final passphrase = generatePassphrase();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      passwordController.text = passphrase;
      obscurePassword = false;
    });
    passwordController.selection = TextSelection.collapsed(
      offset: passphrase.length,
    );

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
      const SnackBar(
        content: Text(
          'Generated an 8-word passphrase. Save it somewhere safe.',
        ),
      ),
    );
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
            controller: passwordController,
            obscureText: obscurePassword,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            validator: (value) {
              final password = value ?? '';
              if (password.trim().isEmpty) {
                return null;
              }
              if (password.length < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: hasPassword ? 'Set a new password' : 'Set a password',
              helperText: hasPassword
                  ? 'Leave blank to keep your current password.'
                  : 'Add a password to keep this account after sign out.',
              labelText: hasPassword ? 'Password' : 'Make account permanent',
              suffixIconConstraints: const BoxConstraints(minWidth: 96),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('profile-generate-password-button'),
                    icon: const Icon(Icons.casino_outlined),
                    tooltip: 'Generate a memorable passphrase',
                    onPressed: _fillGeneratedPassphrase,
                  ),
                  IconButton(
                    key: const Key('profile-toggle-password-visibility-button'),
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    tooltip: obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                ],
              ),
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
                  final meModel = Provider.of<MeModel>(context, listen: false);
                  final messenger = ScaffoldMessenger.of(context);
                  _formKey.currentState!.save();
                  final password = passwordController.text;

                  final data = <String, String?>{
                    'username': username,
                    'status': status,
                  };
                  if (password.trim().isNotEmpty) {
                    data['password'] = password;
                  }

                  try {
                    final me = await httpService.update_profile(data);
                    if (!mounted) {
                      return;
                    }
                    meModel.setData(me);

                    messenger.showSnackBar(
                      const SnackBar(content: Text('Profile saved')),
                    );
                  } on UnauthorizedResponse {
                    if (!mounted) {
                      return;
                    }
                    await expireSession(
                      context,
                      httpService: httpService,
                      description: 'Your session has ended. Please sign in again.',
                    );
                  } catch (error) {
                    await showActionErrorDialog(
                      locator<DialogService>(),
                      title: 'Could not save profile',
                      error: error,
                      fallbackDescription:
                          'Your profile could not be saved right now. Try again.',
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
