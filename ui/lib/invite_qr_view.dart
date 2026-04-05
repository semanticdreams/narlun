import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'http.dart';
import 'me_model.dart';
import 'models.dart';
import 'route_utils.dart';

class InviteQrView extends StatefulWidget {
  final RoomSummary? room;
  final int? roomId;

  const InviteQrView({super.key, this.room, this.roomId});

  @override
  State<InviteQrView> createState() => _InviteQrViewState();
}

class _InviteQrViewState extends State<InviteQrView> {
  InviteLink? _invite;
  Object? _error;
  late final HttpService _httpService;
  late final TextEditingController _linkController;

  @override
  void initState() {
    super.initState();
    _httpService = Provider.of<HttpService>(context, listen: false);
    _linkController = TextEditingController();
    unawaited(_loadInvite());
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadInvite() async {
    setState(() {
      _error = null;
      _invite = null;
    });
    try {
      final invite = await _httpService.create_invite(
        roomId: widget.room?.id ?? widget.roomId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _invite = invite;
        _linkController.text = inviteUrlForToken(invite.token);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = describeActionError(
          error,
          fallbackDescription: 'Could not create an invite right now.',
        );
      });
    }
  }

  Future<void> _copyInviteLink(String inviteUrl) async {
    await Clipboard.setData(ClipboardData(text: inviteUrl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Invite link copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final me = Provider.of<MeModel?>(context)?.data;
    final roomLabel = widget.room == null
        ? null
        : (me == null
                  ? (widget.room!.name ?? '')
                  : widget.room!.displayTitleFor(me))
              .trim();
    final title = widget.room == null && widget.roomId == null
        ? 'Invite someone'
        : (roomLabel?.isNotEmpty ?? false)
        ? 'Invite to $roomLabel'
        : 'Invite to this conversation';
    final description = widget.room == null && widget.roomId == null
        ? 'Scan this code to open Narlun. New people can choose a username and land straight in a room with you.'
        : 'Scan this code to open Narlun. New people can choose a username and land straight in this conversation.';

    Widget body;
    if (_error != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error as String,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('Try again in a moment.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadInvite, child: const Text('Try again')),
        ],
      );
    } else if (_invite == null) {
      body = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Creating your invite...'),
        ],
      );
    } else {
      final inviteUrl = inviteUrlForToken(_invite!.token);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 16,
                    color: Color(0x22000000),
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: QrImageView(
                data: inviteUrl,
                size: 280,
                version: QrVersions.auto,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF4B2F75),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF201233),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'This link stays active for 24 hours.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('invite-link-text'),
            controller: _linkController,
            readOnly: true,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Invite link',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                key: const Key('invite-copy-button'),
                onPressed: () => _copyInviteLink(inviteUrl),
                icon: const Icon(Icons.link),
                label: const Text('Copy link'),
              ),
              OutlinedButton.icon(
                onPressed: _loadInvite,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh code'),
              ),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: const Color(0xFFF5ECFF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      body,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
