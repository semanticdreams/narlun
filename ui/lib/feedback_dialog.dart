import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'frontend_error_reporter.dart';
import 'http.dart';
import 'route_utils.dart';

Future<bool> showFeedbackDialog(
  BuildContext context, {
  required String source,
  Map<String, Object?>? details,
}) async {
  final httpService = Provider.of<HttpService>(context, listen: false);
  final route = currentRouteUri(context)?.toString() ?? '/';
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => _FeedbackDialog(
      route: route,
      source: source,
      onSubmit: (message) {
        return httpService.submit_feedback(
          message: message,
          source: source,
          route: route,
          details: details,
          silentErrors: true,
        );
      },
    ),
  );

  return submitted == true;
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
