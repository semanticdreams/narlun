import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'http.dart';
import 'whatsapp_group_links.dart';

class AddWhatsappGroupView extends StatefulWidget {
  const AddWhatsappGroupView({super.key, required this.onAdd});

  final Future<bool> Function(String inviteUrl) onAdd;

  @override
  State<AddWhatsappGroupView> createState() => _AddWhatsappGroupViewState();
}

class _AddWhatsappGroupViewState extends State<AddWhatsappGroupView> {
  final TextEditingController _inviteController = TextEditingController();
  String? _errorText;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    if (_isSubmitting) {
      return;
    }
    try {
      final clipboardData = await Clipboard.getData('text/plain');
      final pastedText = clipboardData?.text?.trim();
      if (!mounted || pastedText == null || pastedText.isEmpty) {
        return;
      }
      _inviteController.value = TextEditingValue(
        text: pastedText,
        selection: TextSelection.collapsed(offset: pastedText.length),
      );
      if (_errorText != null) {
        setState(() {
          _errorText = null;
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not paste right now.')),
        );
    }
  }

  Future<void> _submit() async {
    final normalizedUrl = normalizeWhatsappGroupInviteUrl(
      _inviteController.text,
    );
    if (normalizedUrl == null) {
      setState(() {
        _errorText =
            'Enter a valid WhatsApp invite link from chat.whatsapp.com.';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final added = await widget.onAdd(normalizedUrl);
      if (added && mounted) {
        Navigator.of(context).pop();
      }
    } on InvalidUsage catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildStep(int number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFE3F2E2),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF285B34),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF33423D)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3E8DA),
        appBar: AppBar(
          title: const Text('Add WhatsApp group'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isSubmitting
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create a WhatsApp group or use one you already manage, then paste its invite link here.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF2A3A35),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStep(
                          1,
                          'Open WhatsApp and create a group, or open an existing group.',
                        ),
                        const SizedBox(height: 14),
                        _buildStep(2, 'Copy the invite link for that group.'),
                        const SizedBox(height: 14),
                        _buildStep(
                          3,
                          'Paste the link below to add a join card to this room.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('whatsapp-group-link-field'),
                        controller: _inviteController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (_errorText == null) {
                            return;
                          }
                          setState(() {
                            _errorText = null;
                          });
                        },
                        onSubmitted: (_) async {
                          await _submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'WhatsApp invite link',
                          hintText: 'https://chat.whatsapp.com/...',
                          errorText: _errorText,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      key: const Key('whatsapp-group-paste-button'),
                      onPressed: _isSubmitting ? null : _pasteFromClipboard,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(52, 56),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.content_paste_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('whatsapp-group-add-submit-button'),
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.group_add_rounded),
                    label: Text(_isSubmitting ? 'Adding...' : 'Add'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
