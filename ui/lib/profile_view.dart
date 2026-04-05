import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'dialog_service.dart';
import 'http.dart';
import 'image_picker.dart';
import 'install_prompt_actions.dart';
import 'install_prompt_service.dart';
import 'frontend_error_reporter.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'profile_form.dart';
import 'push_notifications_service.dart';
import 'route_utils.dart';
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
  bool _reportedProfileNotificationControls = false;
  bool _reportedProfileInstallAction = false;
  bool _reportedProfileFeedbackAction = false;

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

  Future<void> _deleteAccount(BuildContext context) async {
    final httpService = Provider.of<HttpService>(context, listen: false);
    final resolvedDialogService =
        widget.dialogService ?? locator<DialogService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This removes your account and avatar. Rooms that end up with no meaningful membership left may also disappear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await httpService.delete_account();
        if (!context.mounted) {
          return;
        }
        Provider.of<MeModel>(context, listen: false).reset();
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      } on UnauthorizedResponse {
        if (!context.mounted) {
          return;
        }
        await expireSession(
          context,
          httpService: httpService,
          description: 'Your session has ended. Please sign in again.',
        );
      } catch (error) {
        await showActionErrorDialog(
          resolvedDialogService,
          title: 'Could not delete account',
          error: error,
          fallbackDescription:
              'Your account could not be deleted right now. Try again.',
        );
      }
    }
  }

  Future<void> _showFeedbackDialog() async {
    final httpService = Provider.of<HttpService>(context, listen: false);
    final route = currentRouteUri(context)?.toString() ?? '/profile';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => _FeedbackDialog(
        route: route,
        source: 'profile',
        onSubmit: (message) {
          return httpService.submit_feedback(
            message: message,
            source: 'profile',
            route: route,
            details: const {'surface': 'profile'},
            silentErrors: true,
          );
        },
      ),
    );

    if (submitted != true || !mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Feedback sent. Thank you.')));
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
                                title: 'Could not upload picture',
                                error: error,
                                fallbackDescription:
                                    'The picture could not be uploaded right now. Try again.',
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
                  Consumer<PushNotificationsService>(
                    builder: (context, pushService, child) {
                      if (currentUser?.authenticated != true ||
                          !pushService.isSupported) {
                        return const SizedBox.shrink();
                      }

                      final statusMessage = pushService.statusMessage;
                      final canShowAction =
                          pushService.isConfigured || pushService.isSubscribed;
                      if (canShowAction &&
                          !_reportedProfileNotificationControls) {
                        _reportedProfileNotificationControls = true;
                        logFrontendDiagnostic(
                          'profile_notification_controls_visible',
                          'Profile screen displayed notification controls.',
                          details: {
                            'is_subscribed': pushService.isSubscribed,
                            'is_configured': pushService.isConfigured,
                            'permission_state':
                                pushService.permissionState.name,
                          },
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (canShowAction)
                                OutlinedButton.icon(
                                  onPressed: pushService.isBusy
                                      ? null
                                      : () async {
                                          final resolvedDialogService =
                                              widget.dialogService ??
                                              locator<DialogService>();
                                          try {
                                            if (pushService.isSubscribed) {
                                              await pushService
                                                  .disableNotifications();
                                            } else {
                                              await pushService
                                                  .enableNotifications();
                                            }
                                          } catch (error) {
                                            await showActionErrorDialog(
                                              resolvedDialogService,
                                              title:
                                                  'Could not update notifications',
                                              error: error,
                                              fallbackDescription:
                                                  'Notification settings could not be updated right now.',
                                            );
                                          }
                                        },
                                  icon: Icon(
                                    pushService.isSubscribed
                                        ? Icons.notifications_off_outlined
                                        : Icons.notifications_active_outlined,
                                  ),
                                  label: Text(
                                    pushService.isSubscribed
                                        ? 'Turn off notifications'
                                        : 'Turn on notifications',
                                  ),
                                ),
                              if (statusMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(statusMessage),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Consumer<InstallPromptService>(
                    builder: (context, installPromptService, child) {
                      if (!installPromptService.isInstallAvailable) {
                        return const SizedBox.shrink();
                      }
                      if (!_reportedProfileInstallAction) {
                        _reportedProfileInstallAction = true;
                        logFrontendDiagnostic(
                          'profile_install_action_visible',
                          'Profile screen displayed the install action.',
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              handleInstallRequest(
                                context,
                                installPromptService,
                              );
                            },
                            icon: const Icon(
                              Icons.download_for_offline_outlined,
                            ),
                            label: const Text('Install app'),
                          ),
                        ),
                      );
                    },
                  ),
                  if (currentUser?.authenticated == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _showFeedbackDialog,
                          icon: const Icon(Icons.bug_report_outlined),
                          label: const Text('Send feedback'),
                        ),
                      ),
                    ),
                  if (currentUser?.authenticated == true &&
                      !_reportedProfileFeedbackAction)
                    Builder(
                      builder: (context) {
                        _reportedProfileFeedbackAction = true;
                        logFrontendDiagnostic(
                          'profile_feedback_action_visible',
                          'Profile screen displayed the feedback action.',
                        );
                        return const SizedBox.shrink();
                      },
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _deleteAccount(context),
                      child: const Text('Delete account'),
                    ),
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

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({
    required this.route,
    required this.source,
    required this.onSubmit,
  });

  final String route;
  final String source;
  final Future<String?> Function(String message) onSubmit;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final requestId = await widget.onSubmit(message);
      logFrontendDiagnostic(
        'feedback_submitted',
        'User submitted in-app feedback.',
        details: {
          'route': widget.route,
          'source': widget.source,
          'feedback_request_id': requestId,
        },
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      logFrontendDiagnostic(
        'feedback_submit_failed',
        'Could not submit in-app feedback.',
        details: {
          'route': widget.route,
          'source': widget.source,
          'error': error.toString(),
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = describeActionError(
          error,
          fallbackDescription:
              'Feedback could not be sent right now. Please try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !_isSubmitting && _messageController.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Send feedback'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tell us what happened or what should be improved. Your account, page, and session context will be attached so we can trace it in the logs.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('feedback-message-field'),
              controller: _messageController,
              autofocus: true,
              enabled: !_isSubmitting,
              maxLength: 2000,
              maxLines: 6,
              minLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Describe the issue or idea',
                errorText: _errorMessage,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSend ? _submit : null,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
