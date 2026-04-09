import 'dart:async';

import 'package:flutter/material.dart';

import 'avatar_image.dart';
import 'http.dart';
import 'models.dart';

class AddOtherRoomView extends StatefulWidget {
  const AddOtherRoomView({
    super.key,
    required this.httpService,
    required this.me,
    required this.currentRoomId,
    required this.onAdd,
  });

  final HttpService httpService;
  final SessionUser me;
  final int currentRoomId;
  final Future<bool> Function(RoomSummary room) onAdd;

  @override
  State<AddOtherRoomView> createState() => _AddOtherRoomViewState();
}

class _AddOtherRoomViewState extends State<AddOtherRoomView> {
  List<RoomSummary> _rooms = const [];
  String? _errorText;
  bool _isLoading = true;
  int? _submittingRoomId;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRooms());
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final rooms = await widget.httpService.get_rooms(silentErrors: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms = rooms
            .where((room) => room.id != widget.currentRoomId)
            .toList(growable: false);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms = const [];
        _isLoading = false;
        _errorText = 'Could not load your rooms right now.';
      });
    }
  }

  Future<void> _submit(RoomSummary room) async {
    if (_submittingRoomId != null) {
      return;
    }
    setState(() {
      _submittingRoomId = room.id;
    });
    try {
      final added = await widget.onAdd(room);
      if (added && mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _submittingRoomId = null;
        });
      }
    }
  }

  String _memberCountLabel(RoomSummary room) {
    final count = room.memberCount;
    return '$count member${count == 1 ? '' : 's'}';
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF2A3A35),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('other-room-retry-button'),
                onPressed: _loadRooms,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'You do not have another room to share yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF2A3A35),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      itemCount: _rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final room = _rooms[index];
        final isSubmitting = _submittingRoomId == room.id;
        return Material(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            key: Key('other-room-option-${room.id}'),
            borderRadius: BorderRadius.circular(24),
            onTap: isSubmitting ? null : () => _submit(room),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AvatarImage(
                    picture: room.displayPictureFor(widget.me),
                    radius: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.displayTitleFor(widget.me),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: const Color(0xFF1F2528),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _memberCountLabel(room),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF5E6967)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: isSubmitting ? null : () => _submit(room),
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(isSubmitting ? 'Adding...' : 'Add'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = _submittingRoomId != null;
    return PopScope<void>(
      canPop: !isSubmitting,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3E8DA),
        appBar: AppBar(
          title: const Text('Share another room'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: isSubmitting
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text(
                  'Pick one of your other rooms to post a direct join card here.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF2A3A35),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }
}
