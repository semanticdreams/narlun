import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'http.dart';
import 'locator.dart';
import 'models.dart';
import 'random_statuses.dart';
import 'session_actions.dart';
import 'websocket.dart';

class RoomDetailsView extends StatefulWidget {
  final RoomSummary room;
  final SessionUser me;
  final HttpService? httpService;
  final WebsocketService? websocketService;
  final ValueChanged<RoomSummary>? onRoomChanged;

  const RoomDetailsView({
    super.key,
    required this.room,
    required this.me,
    this.httpService,
    this.websocketService,
    this.onRoomChanged,
  });

  @override
  State<RoomDetailsView> createState() => _RoomDetailsViewState();
}

class _RoomDetailsViewState extends State<RoomDetailsView> {
  static const _renameDebounce = Duration(milliseconds: 500);

  late final HttpService httpService;
  late final WebsocketService websocketService;
  late final TextEditingController _nameController;
  late RoomSummary room;

  StreamSubscription? _roomsChangedSubscription;
  StreamSubscription? _roomDeletedSubscription;
  StreamSubscription? _connectionEventsSubscription;
  Timer? _renameDebounceTimer;

  bool _isApplyingNameText = false;
  bool _isSavingName = false;
  bool _isUpdatingPushMuted = false;
  bool _roomClosed = false;
  String? _nameErrorText;

  String _editableNameFor(RoomSummary candidate) {
    final explicitName = candidate.name?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }
    return candidate.displayTitleFor(widget.me);
  }

  String _normalizedRoomName(RoomSummary candidate) {
    return _editableNameFor(candidate).trim();
  }

  String _normalizedInputName() {
    return _nameController.text.trim();
  }

  bool _shouldAcceptRoomUpdate(RoomSummary candidate) {
    return !candidate.updatedAt.isBefore(room.updatedAt);
  }

  void _setNameFieldValue(String value) {
    _isApplyingNameText = true;
    _nameController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _isApplyingNameText = false;
  }

  void _applyRoomUpdate(RoomSummary candidate) {
    if (!_shouldAcceptRoomUpdate(candidate)) {
      return;
    }
    final nextName = _editableNameFor(candidate);
    final shouldReplaceInput = _nameController.text != nextName;
    setState(() {
      room = candidate;
      if (_normalizedInputName().isNotEmpty) {
        _nameErrorText = null;
      }
    });
    if (shouldReplaceInput) {
      _setNameFieldValue(nextName);
    }
    widget.onRoomChanged?.call(candidate);
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleRoomDeleted() async {
    if (_roomClosed || !mounted) {
      return;
    }
    _roomClosed = true;
    _showSnackBar('This room is no longer available.');
    Navigator.of(context).pop();
  }

  Future<void> _handleSessionEnded() async {
    if (_roomClosed || !mounted) {
      return;
    }
    _roomClosed = true;
    await expireSession(
      context,
      httpService: httpService,
      description: 'Your session has ended. Please sign in again.',
    );
  }

  Future<void> _refreshRoomSummary({bool silentErrors = false}) async {
    try {
      final rooms = await httpService.get_rooms(silentErrors: silentErrors);
      if (!mounted || _roomClosed) {
        return;
      }
      final updatedRoom = rooms.where((candidate) => candidate.id == room.id);
      if (updatedRoom.isEmpty) {
        await _handleRoomDeleted();
        return;
      }
      _applyRoomUpdate(updatedRoom.first);
    } on UnauthorizedResponse {
      await _handleSessionEnded();
    } catch (_) {
      if (!silentErrors && mounted && !_roomClosed) {
        _showSnackBar('Could not refresh this room right now.');
      }
    }
  }

  Future<void> _saveRoomName() async {
    final nextName = _normalizedInputName();
    if (!mounted || _roomClosed) {
      return;
    }
    if (nextName.isEmpty) {
      setState(() {
        _nameErrorText = 'Room name cannot be empty.';
        _isSavingName = false;
      });
      return;
    }
    if (nextName == _normalizedRoomName(room)) {
      setState(() {
        _nameErrorText = null;
        _isSavingName = false;
      });
      return;
    }

    setState(() {
      _nameErrorText = null;
      _isSavingName = true;
    });
    try {
      final updatedRoom = await httpService.update_room_settings(
        room.id,
        name: nextName,
      );
      if (!mounted || _roomClosed) {
        return;
      }
      _applyRoomUpdate(updatedRoom);
    } on UnauthorizedResponse {
      await _handleSessionEnded();
    } catch (error) {
      if (!mounted || _roomClosed) {
        return;
      }
      if (!isAlreadyPresentedActionError(error)) {
        _showSnackBar(
          describeActionError(
            error,
            fallbackDescription: 'Could not update the room name right now.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingName = false;
        });
      }
    }
  }

  void _scheduleNameSave() {
    _renameDebounceTimer?.cancel();
    _renameDebounceTimer = Timer(_renameDebounce, () {
      unawaited(_saveRoomName());
    });
  }

  void _handleNameChanged() {
    if (_isApplyingNameText || _roomClosed) {
      return;
    }
    final nextName = _normalizedInputName();
    setState(() {
      _nameErrorText = nextName.isEmpty ? 'Room name cannot be empty.' : null;
    });
    _scheduleNameSave();
  }

  Future<void> _updatePushMuted(bool pushMuted) async {
    if (_isUpdatingPushMuted) {
      return;
    }
    setState(() {
      _isUpdatingPushMuted = true;
    });
    try {
      final updatedRoom = await httpService.update_room_settings(
        room.id,
        pushMuted: pushMuted,
      );
      if (!mounted || _roomClosed) {
        return;
      }
      _applyRoomUpdate(updatedRoom);
      _showSnackBar(
        pushMuted
            ? 'Notifications muted for this room.'
            : 'Notifications restored for this room.',
      );
    } on UnauthorizedResponse {
      await _handleSessionEnded();
    } catch (error) {
      if (!mounted || _roomClosed) {
        return;
      }
      if (!isAlreadyPresentedActionError(error)) {
        _showSnackBar(
          describeActionError(
            error,
            fallbackDescription:
                'Could not update notification settings right now.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPushMuted = false;
        });
      }
    }
  }

  void _fillRandomName() {
    final generatedName = pickRandomStatus(excluding: _nameController.text);
    _setNameFieldValue(generatedName);
    _handleNameChanged();
  }

  @override
  void initState() {
    super.initState();
    httpService =
        widget.httpService ?? Provider.of<HttpService>(context, listen: false);
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    room = widget.room;
    _nameController = TextEditingController(text: _editableNameFor(room));
    _nameController.addListener(_handleNameChanged);
    _roomsChangedSubscription = websocketService.roomsChangedStream().listen((
      _,
    ) {
      unawaited(_refreshRoomSummary(silentErrors: true));
    });
    _roomDeletedSubscription = websocketService
        .roomDeletedStream(room.id)
        .listen((_) {
          unawaited(_handleRoomDeleted());
        });
    _connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) {
      if (event == 'reconnected') {
        unawaited(_refreshRoomSummary(silentErrors: true));
      } else if (event == 'signed-out') {
        unawaited(_handleSessionEnded());
      }
    });
  }

  @override
  void dispose() {
    _renameDebounceTimer?.cancel();
    _roomsChangedSubscription?.cancel();
    _roomDeletedSubscription?.cancel();
    _connectionEventsSubscription?.cancel();
    _nameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Room details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                AvatarImage(
                  picture: room.displayPictureFor(widget.me),
                  radius: 38,
                ),
                const SizedBox(height: 12),
                Text(
                  room.displayTitleFor(widget.me),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  room.memberCount == 1
                      ? '1 member'
                      : '${room.memberCount} members',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextField(
            key: const Key('room-details-name-input'),
            controller: _nameController,
            textInputAction: TextInputAction.done,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: 'Room name',
              helperText: _isSavingName
                  ? 'Saving for everyone...'
                  : 'Autosaves for everyone',
              errorText: _nameErrorText,
              suffixIcon: IconButton(
                key: const Key('room-details-generate-name-button'),
                icon: const Icon(Icons.casino_outlined),
                tooltip: 'Generate random room name',
                onPressed: _fillRandomName,
              ),
            ),
            onSubmitted: (_) {
              _renameDebounceTimer?.cancel();
              unawaited(_saveRoomName());
            },
          ),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              value: room.pushMuted,
              onChanged: _isUpdatingPushMuted ? null : _updatePushMuted,
              title: const Text('Mute notifications'),
              subtitle: const Text('Only changes notifications for you.'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Members',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < room.participants.length; i += 1) ...[
                  ListTile(
                    leading: AvatarImage(
                      picture: room.participants[i].picture,
                      radius: 20,
                    ),
                    title: Text(room.participants[i].username),
                  ),
                  if (i < room.participants.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
