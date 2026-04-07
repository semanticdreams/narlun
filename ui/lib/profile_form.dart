import 'dart:async';

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
  static const autosaveDelay = Duration(milliseconds: 2200);

  late final HttpService httpService;
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final statusController = TextEditingController();

  late String _savedUsername;
  String _savedPassword = '';
  late String _savedStatus;
  bool _hasUnsavedChanges = false;
  bool obscurePassword = true;
  bool _passwordVisibilityInitialized = false;
  bool _suppressFieldChange = false;
  Timer? _autosaveTimer;
  Future<bool>? _saveOperation;

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
    if (_hasUnsavedChanges || _saveOperation != null) {
      return;
    }
    if (oldWidget.data == widget.data) {
      return;
    }
    _savedUsername = widget.data.username ?? '';
    _savedStatus = widget.data.status ?? '';
    _replaceFormValues(clearPassword: false);
    _updateDirtyState();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
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
    if (_suppressFieldChange) {
      return;
    }
    if (!_passwordVisibilityInitialized && passwordController.text.isNotEmpty) {
      _passwordVisibilityInitialized = true;
      if (obscurePassword) {
        setState(() {
          obscurePassword = false;
        });
      }
    }
    _updateDirtyState();
    _scheduleAutosave();
  }

  void _updateDirtyState() {
    final passwordNeedsSave =
        passwordController.text.trim().isNotEmpty &&
        passwordController.text != _savedPassword;
    final nextHasUnsavedChanges =
        usernameController.text != _savedUsername ||
        statusController.text != _savedStatus ||
        passwordNeedsSave;
    if (nextHasUnsavedChanges == _hasUnsavedChanges) {
      return;
    }
    setState(() {
      _hasUnsavedChanges = nextHasUnsavedChanges;
    });
    widget.onDirtyChanged?.call(_hasUnsavedChanges);
  }

  void _applySavedProfile(
    SessionUser me, {
    required String submittedUsername,
    required String submittedStatusInput,
    required String submittedPassword,
  }) {
    _savedUsername = me.username ?? '';
    _savedStatus = me.status ?? '';
    if (submittedPassword.trim().isNotEmpty &&
        passwordController.text == submittedPassword) {
      _savedPassword = submittedPassword;
    }
    final preserveUsername = usernameController.text != submittedUsername;
    final preserveStatus = statusController.text != submittedStatusInput;

    _suppressFieldChange = true;
    if (!preserveUsername) {
      usernameController.text = _savedUsername;
    }
    if (!preserveStatus) {
      statusController.text = _savedStatus;
    }
    _suppressFieldChange = false;
    _updateDirtyState();
  }

  void _replaceFormValues({required bool clearPassword}) {
    _suppressFieldChange = true;
    usernameController.text = _savedUsername;
    statusController.text = _savedStatus;
    if (clearPassword) {
      _savedPassword = '';
      passwordController.clear();
    }
    _suppressFieldChange = false;
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (!_hasUnsavedChanges) {
      return;
    }
    _autosaveTimer = Timer(autosaveDelay, () {
      unawaited(
        saveProfile(showSuccessMessage: true, showValidationErrors: false),
      );
    });
  }

  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username can\'t be empty';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.trim().isEmpty) {
      return null;
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  bool _canSaveCurrentValues({required bool showValidationErrors}) {
    if (showValidationErrors) {
      return _formKey.currentState!.validate();
    }
    return _validateUsername(usernameController.text) == null &&
        _validatePassword(passwordController.text) == null;
  }

  void _fillGeneratedPassphrase() {
    final passphrase = generatePassphrase();
    final messenger = ScaffoldMessenger.of(context);
    _passwordVisibilityInitialized = true;
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

  Future<bool> flushPendingChanges({bool showSuccessMessage = true}) async {
    _autosaveTimer?.cancel();
    final ongoingSave = _saveOperation;
    if (ongoingSave != null) {
      final result = await ongoingSave;
      if (!_hasUnsavedChanges || !mounted) {
        return result;
      }
    }
    if (!_hasUnsavedChanges) {
      return true;
    }
    return saveProfile(
      showSuccessMessage: showSuccessMessage,
      showValidationErrors: true,
    );
  }

  Future<bool> saveProfile({
    bool showSuccessMessage = true,
    bool showValidationErrors = true,
  }) async {
    _autosaveTimer?.cancel();
    final ongoingSave = _saveOperation;
    if (ongoingSave != null) {
      final result = await ongoingSave;
      if (!_hasUnsavedChanges || !mounted) {
        return result;
      }
    }
    if (!_hasUnsavedChanges) {
      return true;
    }
    if (!_canSaveCurrentValues(showValidationErrors: showValidationErrors)) {
      return false;
    }

    final saveFuture = _saveCurrentProfile(
      showSuccessMessage: showSuccessMessage,
    );
    _saveOperation = saveFuture;
    final result = await saveFuture;
    if (identical(_saveOperation, saveFuture)) {
      _saveOperation = null;
    }
    if (_hasUnsavedChanges) {
      _scheduleAutosave();
    }
    return result;
  }

  Future<bool> _saveCurrentProfile({required bool showSuccessMessage}) async {
    final meModel = Provider.of<MeModel>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final username = usernameController.text;
    final statusInput = statusController.text;
    final status = statusInput.trim();
    final password = passwordController.text;
    final passwordChanged =
        password.trim().isNotEmpty && password != _savedPassword;
    final shouldSaveCredentials =
        username != _savedUsername ||
        (passwordChanged && password.trim().isNotEmpty);

    final data = <String, String?>{'username': username, 'status': status};
    if (passwordChanged && password.trim().isNotEmpty) {
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
      _applySavedProfile(
        me,
        submittedUsername: username,
        submittedStatusInput: statusInput,
        submittedPassword: password,
      );

      if (showSuccessMessage) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Profile changes saved')),
          );
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
                    return _validateUsername(value);
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
                    return _validatePassword(value);
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
          if (!hasPassword)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Without a password this account will be deleted on sign out.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
