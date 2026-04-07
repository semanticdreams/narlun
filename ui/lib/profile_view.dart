import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'appbar_avatar.dart';
import 'avatar_image.dart';
import 'dialog_service.dart';
import 'http.dart';
import 'image_picker.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'profile_form.dart';
import 'session_actions.dart';

enum _UnsavedProfileAction { save, discard }

class ProfileView extends StatefulWidget {
  final Future<Uint8List?> Function()? imagePicker;
  final DialogService? dialogService;

  const ProfileView({super.key, this.imagePicker, this.dialogService});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _profileFormKey = GlobalKey<ProfileFormState>();
  bool _hasUnsavedChanges = false;
  bool _allowImmediatePop = false;
  bool _isResolvingPop = false;

  Future<bool> _resolveUnsavedChanges() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final action = await showDialog<_UnsavedProfileAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text(
          'You have unsaved profile changes. Save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _UnsavedProfileAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _UnsavedProfileAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    switch (action) {
      case _UnsavedProfileAction.save:
        return await _profileFormKey.currentState?.saveProfile(
              showSuccessMessage: false,
            ) ??
            false;
      case _UnsavedProfileAction.discard:
        return true;
      case null:
        return false;
    }
  }

  Future<void> _attemptPop() async {
    if (_isResolvingPop) {
      return;
    }
    if (!_hasUnsavedChanges) {
      await Navigator.of(context).maybePop();
      return;
    }

    _isResolvingPop = true;
    final shouldPop = await _resolveUnsavedChanges();
    if (!mounted) {
      return;
    }
    _isResolvingPop = false;
    if (!shouldPop) {
      return;
    }

    setState(() {
      _allowImmediatePop = true;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }

    final didPop = await Navigator.of(context).maybePop();
    if (!mounted || didPop) {
      return;
    }

    setState(() {
      _allowImmediatePop = false;
    });
  }

  Future<void> _openSettings() async {
    if (_isResolvingPop) {
      return;
    }
    final shouldLeave = await _resolveUnsavedChanges();
    if (!mounted || !shouldLeave) {
      return;
    }
    Navigator.of(context).pushReplacementNamed('/settings');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _allowImmediatePop || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _attemptPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: [AppBarAvatar(onOpenSettings: _openSettings)],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _attemptPop,
          ),
        ),
        body: Consumer<MeModel>(
          builder: (context, me, child) {
            final SessionUser? currentUser = me.data;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        alignment: Alignment.center,
                        child: AvatarImage(
                          picture: currentUser?.picture,
                          radius: 64,
                        ),
                      ),
                      Container(
                        alignment: Alignment.topRight,
                        child: TextButton(
                          child: const Text('Upload picture'),
                          onPressed: () async {
                            final httpService = Provider.of<HttpService>(
                              context,
                              listen: false,
                            );
                            final resolvedDialogService =
                                widget.dialogService ??
                                locator<DialogService>();
                            try {
                              final file =
                                  await (widget.imagePicker ??
                                      pickImageBytes)();
                              if (file == null) {
                                return;
                              }
                              final picture = await httpService
                                  .upload_profile_picture(file);
                              if (!context.mounted) {
                                return;
                              }
                              Provider.of<MeModel>(
                                context,
                                listen: false,
                              ).setProfilePicture(picture);

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Profile picture saved'),
                                ),
                              );
                            } on UnauthorizedResponse {
                              if (!context.mounted) {
                                return;
                              }
                              await expireSession(
                                context,
                                httpService: httpService,
                                description:
                                    'Your session has ended. Please sign in again.',
                              );
                            } catch (error) {
                              await showActionErrorDialog(
                                resolvedDialogService,
                                title: 'Upload failed',
                                error: error,
                                fallbackDescription:
                                    'Upload failed. Try again later.',
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (currentUser != null)
                    ProfileForm(
                      key: _profileFormKey,
                      data: currentUser,
                      onDirtyChanged: (hasUnsavedChanges) {
                        if (_hasUnsavedChanges == hasUnsavedChanges) {
                          return;
                        }
                        setState(() {
                          _hasUnsavedChanges = hasUnsavedChanges;
                        });
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
