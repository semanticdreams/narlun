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

class ProfileView extends StatefulWidget {
  final Future<Uint8List?> Function()? imagePicker;
  final DialogService? dialogService;

  const ProfileView({super.key, this.imagePicker, this.dialogService});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _profileFormKey = GlobalKey<ProfileFormState>();
  bool _allowImmediatePop = false;
  bool _isResolvingPop = false;
  Future<bool>? _pictureSaveOperation;
  bool _isUploadingPicture = false;

  Future<void> _attemptPop() async {
    if (_isResolvingPop) {
      return;
    }

    _isResolvingPop = true;
    final shouldPop = await _flushPendingProfileChanges();
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

  Future<bool> _flushPendingProfileChanges() async {
    final pictureSave = _pictureSaveOperation;
    if (pictureSave != null) {
      final result = await pictureSave;
      if (!result) {
        return false;
      }
    }
    return await _profileFormKey.currentState?.flushPendingChanges() ?? true;
  }

  Future<void> _openSettings() async {
    if (_isResolvingPop) {
      return;
    }
    _isResolvingPop = true;
    final shouldLeave = await _flushPendingProfileChanges();
    if (!mounted || !shouldLeave) {
      _isResolvingPop = false;
      return;
    }
    _isResolvingPop = false;
    Navigator.of(context).pushReplacementNamed('/settings');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _allowImmediatePop,
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
                          onPressed: _isUploadingPicture
                              ? null
                              : () async {
                                  final saveFuture = _saveProfilePicture();
                                  _pictureSaveOperation = saveFuture;
                                  final result = await saveFuture;
                                  if (!mounted ||
                                      !identical(
                                        _pictureSaveOperation,
                                        saveFuture,
                                      )) {
                                    return;
                                  }
                                  _pictureSaveOperation = null;
                                  if (!result) {
                                    return;
                                  }
                                },
                          child: const Text('Upload picture'),
                        ),
                      ),
                    ],
                  ),
                  if (currentUser != null)
                    ProfileForm(key: _profileFormKey, data: currentUser),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<bool> _saveProfilePicture() async {
    final httpService = Provider.of<HttpService>(context, listen: false);
    final meModel = Provider.of<MeModel>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final resolvedDialogService =
        widget.dialogService ?? locator<DialogService>();
    try {
      setState(() {
        _isUploadingPicture = true;
      });
      final file = await (widget.imagePicker ?? pickImageBytes)();
      if (file == null) {
        return false;
      }
      final picture = await httpService.upload_profile_picture(file);
      if (!mounted) {
        return false;
      }
      meModel.setProfilePicture(picture);

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Profile changes saved')));
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
        resolvedDialogService,
        title: 'Upload failed',
        error: error,
        fallbackDescription: 'Upload failed. Try again later.',
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPicture = false;
        });
      }
    }
  }
}
