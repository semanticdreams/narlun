import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'http.dart';
import 'invite_qr_cache.dart';
import 'me_model.dart';
import 'models.dart';
import 'route_utils.dart';

Future<void> _copyInviteLink(BuildContext context, String inviteUrl) async {
  await Clipboard.setData(ClipboardData(text: inviteUrl));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Invite link copied.')));
}

class InviteQrView extends StatelessWidget {
  final RoomSummary? room;
  final int? roomId;
  final String? backToRoute;
  final bool preferPopOnBack;
  final InviteQrCache? inviteQrCache;

  const InviteQrView({
    super.key,
    this.room,
    this.roomId,
    this.backToRoute,
    this.preferPopOnBack = false,
    this.inviteQrCache,
  });

  int? get _targetRoomId => room?.id ?? roomId;

  @override
  Widget build(BuildContext context) {
    final targetRoomId = _targetRoomId;
    if (targetRoomId == null) {
      return _GlobalInviteQrView(
        backToRoute: backToRoute,
        preferPopOnBack: preferPopOnBack,
      );
    }
    return _RoomInviteQrView(
      room: room,
      roomId: targetRoomId,
      backToRoute: backToRoute,
      preferPopOnBack: preferPopOnBack,
      inviteQrCache: inviteQrCache,
    );
  }
}

class _GlobalInviteQrView extends StatelessWidget {
  final String? backToRoute;
  final bool preferPopOnBack;

  const _GlobalInviteQrView({
    required this.backToRoute,
    required this.preferPopOnBack,
  });

  @override
  Widget build(BuildContext context) {
    final inviteUrl = globalInviteUrl();
    return _InviteQrShell(
      title: 'Invite to Narlun',
      description:
          'Scan this code to open Narlun. New people can choose a username and get started right away.',
      fallbackRoute: sanitizeInviteBackToRoute(backToRoute) ?? '/home',
      preferPopOnBack: preferPopOnBack,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: inviteUrl,
            size: 220,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('invite-link-text'),
                  initialValue: inviteUrl,
                  readOnly: true,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Link',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                key: const Key('invite-copy-button'),
                onPressed: () => _copyInviteLink(context, inviteUrl),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomInviteQrView extends StatefulWidget {
  final RoomSummary? room;
  final int roomId;
  final String? backToRoute;
  final bool preferPopOnBack;
  final InviteQrCache? inviteQrCache;

  const _RoomInviteQrView({
    required this.room,
    required this.roomId,
    required this.backToRoute,
    required this.preferPopOnBack,
    required this.inviteQrCache,
  });

  @override
  State<_RoomInviteQrView> createState() => _RoomInviteQrViewState();
}

class _RoomInviteQrViewState extends State<_RoomInviteQrView> {
  InviteLink? _invite;
  Object? _error;
  bool _loading = false;
  late final HttpService _httpService;
  late final InviteQrCache _inviteQrCache;
  late final TextEditingController _linkController;
  int? _sessionUserId;

  @override
  void initState() {
    super.initState();
    _httpService = Provider.of<HttpService>(context, listen: false);
    final providedInviteQrCache = Provider.of<InviteQrCache?>(
      context,
      listen: false,
    );
    _inviteQrCache =
        widget.inviteQrCache ?? providedInviteQrCache ?? InviteQrCache();
    _linkController = TextEditingController();
    final session = Provider.of<MeModel?>(context, listen: false)?.data;
    _syncInviteCacheSession(session);
    final cachedInvite = _inviteQrCache.cachedInviteFor(roomId: widget.roomId);
    if (cachedInvite != null) {
      _applyInvite(cachedInvite);
    } else {
      unawaited(_loadInvite());
    }
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = Provider.of<MeModel?>(context)?.data;
    if (!_syncInviteCacheSession(session)) {
      return;
    }
    final cachedInvite = _inviteQrCache.cachedInviteFor(roomId: widget.roomId);
    if (cachedInvite != null) {
      setState(() {
        _error = null;
        _loading = false;
        _applyInvite(cachedInvite);
      });
      return;
    }
    setState(() {
      _invite = null;
      _error = null;
      _loading = false;
      _linkController.clear();
    });
    unawaited(_loadInvite());
  }

  @override
  void didUpdateWidget(covariant _RoomInviteQrView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId == widget.roomId) {
      return;
    }
    final cachedInvite = _inviteQrCache.cachedInviteFor(roomId: widget.roomId);
    if (cachedInvite != null) {
      setState(() {
        _error = null;
        _loading = false;
        _applyInvite(cachedInvite);
      });
      return;
    }
    setState(() {
      _invite = null;
      _error = null;
      _loading = false;
      _linkController.clear();
    });
    unawaited(_loadInvite());
  }

  bool _syncInviteCacheSession(SessionUser? session) {
    final nextUserId = session?.authenticated == true && session?.id != null
        ? session!.id
        : null;
    if (_sessionUserId == nextUserId) {
      return false;
    }
    _sessionUserId = nextUserId;
    _inviteQrCache.syncSession(session);
    return true;
  }

  void _applyInvite(InviteLink invite) {
    _invite = invite;
    _linkController.text = inviteUrlForToken(invite.token);
  }

  Future<void> _loadInvite({bool forceRefresh = false}) async {
    final hadInvite = _invite != null;
    setState(() {
      _error = null;
      _loading = true;
      if (!hadInvite) {
        _invite = null;
      }
    });
    try {
      final invite = await _inviteQrCache.loadInvite(
        httpService: _httpService,
        roomId: widget.roomId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _applyInvite(invite);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final description = describeActionError(
        error,
        fallbackDescription: 'Could not create an invite right now.',
      );
      if (hadInvite) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(description)));
        return;
      }
      setState(() {
        _loading = false;
        _error = description;
      });
    }
  }

  Future<void> _refreshInvite() async {
    await _loadInvite(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final me = Provider.of<MeModel?>(context)?.data;
    final displayUser = me ?? const SessionUser(authenticated: false);
    final roomLabel = widget.room?.displayTitleFor(displayUser).trim();
    final title = (roomLabel?.isNotEmpty ?? false)
        ? 'Invite to $roomLabel'
        : 'Invite to this room';
    const description =
        'Scan this code to open Narlun. New people can choose a username and land straight in this room.';

    Widget body;
    if (_error != null && _invite == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error as String,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
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
                onPressed: () => _copyInviteLink(context, inviteUrl),
                icon: const Icon(Icons.link),
                label: const Text('Copy link'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _refreshInvite,
                icon: const Icon(Icons.refresh),
                label: Text(_loading ? 'Refreshing...' : 'Refresh code'),
              ),
            ],
          ),
        ],
      );
    }

    return _InviteQrShell(
      title: title,
      description: description,
      fallbackRoute:
          sanitizeInviteBackToRoute(widget.backToRoute) ??
          roomsRouteWithOpenRoom(widget.roomId),
      preferPopOnBack: widget.preferPopOnBack,
      body: body,
    );
  }
}

class _InviteQrShell extends StatelessWidget {
  final String title;
  final String description;
  final Widget body;
  final String fallbackRoute;
  final bool preferPopOnBack;

  const _InviteQrShell({
    required this.title,
    required this.description,
    required this.body,
    required this.fallbackRoute,
    required this.preferPopOnBack,
  });

  Future<void> _handleBackNavigation(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (preferPopOnBack && navigator.canPop()) {
      navigator.pop();
      return;
    }
    await navigator.pushReplacementNamed(fallbackRoute);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleBackNavigation(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBackNavigation(context),
          ),
        ),
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
      ),
    );
  }
}
