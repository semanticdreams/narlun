import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'dialog_service.dart';
import 'http.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'passphrase_generator.dart';
import 'random_statuses.dart';
import 'session_actions.dart';

const maxStatusLength = 80;

class ProfileForm extends StatefulWidget {
  final SessionUser data;
  final ValueChanged<bool>? onDirtyChanged;

  const ProfileForm({super.key, required this.data, this.onDirtyChanged});

  @override
  ProfileFormState createState() {
    return ProfileFormState();
  }
}

class ProfileFormState extends State<ProfileForm> {
  late final HttpService httpService;
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final statusController = TextEditingController();

  late String _savedUsername;
  late String _savedStatus;
  bool _hasUnsavedChanges = false;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();
    httpService = Provider.of<HttpService>(context, listen: false);
    _savedUsername = widget.data.username ?? '';
    _savedStatus = widget.data.status ?? '';
    usernameController.text = _savedUsername;
    statusController.text = _savedStatus;
    usernameController.addListener(_handleFieldChange);
    passwordController.addListener(_handleFieldChange);
    statusController.addListener(_handleFieldChange);
  }

  @override
  void didUpdateWidget(covariant ProfileForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasUnsavedChanges) {
      return;
    }
    if (oldWidget.data == widget.data) {
      return;
    }
    _savedUsername = widget.data.username ?? '';
    _savedStatus = widget.data.status ?? '';
    usernameController.text = _savedUsername;
    statusController.text = _savedStatus;
    passwordController.clear();
    obscurePassword = true;
    _updateDirtyState();
  }

  @override
  void dispose() {
    usernameController
      ..removeListener(_handleFieldChange)
      ..dispose();
    passwordController
      ..removeListener(_handleFieldChange)
      ..dispose();
    statusController
      ..removeListener(_handleFieldChange)
      ..dispose();
    super.dispose();
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void _handleFieldChange() {
    _updateDirtyState();
  }

  void _updateDirtyState() {
    final nextHasUnsavedChanges =
        usernameController.text != _savedUsername ||
        statusController.text != _savedStatus ||
        passwordController.text.isNotEmpty;
    if (nextHasUnsavedChanges == _hasUnsavedChanges) {
      return;
    }
    setState(() {
      _hasUnsavedChanges = nextHasUnsavedChanges;
    });
    widget.onDirtyChanged?.call(_hasUnsavedChanges);
  }

  void _applySavedProfile(SessionUser me) {
    _savedUsername = me.username ?? '';
    _savedStatus = me.status ?? '';
    usernameController.text = _savedUsername;
    statusController.text = _savedStatus;
    passwordController.clear();
    setState(() {
      obscurePassword = true;
    });
    _updateDirtyState();
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

  void _fillRandomStatus() {
    final nextStatus = pickRandomStatus(excluding: statusController.text);
    statusController.text = nextStatus;
    statusController.selection = TextSelection.collapsed(
      offset: nextStatus.length,
    );
  }

  Future<bool> saveProfile({bool showSuccessMessage = true}) async {
    if (!_formKey.currentState!.validate()) {
      return false;
    }

    final meModel = Provider.of<MeModel>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final username = usernameController.text;
    final status = statusController.text.trim();
    final password = passwordController.text;
    final shouldSaveCredentials =
        username != _savedUsername || password.trim().isNotEmpty;

    final data = <String, String?>{'username': username, 'status': status};
    if (password.trim().isNotEmpty) {
      data['password'] = password;
    }

    try {
      final me = await httpService.update_profile(data);
      if (!mounted) {
        return false;
      }
      meModel.setData(me);
      if (shouldSaveCredentials) {
        TextInput.finishAutofillContext();
      }
      _applySavedProfile(me);

      if (showSuccessMessage) {
        messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
      return true;
    } on UnauthorizedResponse {
      if (!mounted) {
        return false;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
      return false;
    } catch (error) {
      await showActionErrorDialog(
        locator<DialogService>(),
        title: 'Could not save profile',
        error: error,
        fallbackDescription:
            'Your profile could not be saved right now. Try again.',
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = widget.data.hasPassword;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: usernameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newUsername],
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
                    hintText: hasPassword ? '••••••••' : 'Set a password',
                    helperText: hasPassword
                        ? 'A password is already set. Leave blank to keep it, or enter a new one.'
                        : 'Add a password to keep this account after sign out.',
                    labelText: hasPassword
                        ? 'Password'
                        : 'Make account permanent',
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
                          key: const Key(
                            'profile-toggle-password-visibility-button',
                          ),
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
              ],
            ),
          ),
          TextFormField(
            controller: statusController,
            maxLines: 1,
            maxLength: maxStatusLength,
            decoration: InputDecoration(
              hintText: 'Set a short status people see nearby',
              labelText: 'Status',
              suffixIcon: IconButton(
                key: const Key('profile-generate-status-button'),
                icon: const Icon(Icons.casino_outlined),
                tooltip: 'Generate random status',
                onPressed: _fillRandomStatus,
              ),
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
              onPressed: saveProfile,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
