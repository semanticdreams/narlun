import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'chat_labels.dart';
import 'http.dart';
import 'invite_qr_button.dart';
import 'leave_room_notice.dart';
import 'leave_room_notice_storage.dart';
import 'locator.dart';
import 'models.dart';
import 'room_messages_cache.dart';
import 'session_actions.dart';
import 'websocket.dart';

class MessagesView extends StatefulWidget {
  final RoomSummary room;
  final SessionUser me;
  final HttpService? httpService;
  final RoomMessagesCache? roomMessagesCache;
  final WebsocketService? websocketService;

  const MessagesView({
    super.key,
    required this.room,
    required this.me,
    this.httpService,
    this.roomMessagesCache,
    this.websocketService,
  });

  @override
  State<MessagesView> createState() => MessagesState();
}

class MessagesState extends State<MessagesView> {
  static const _typingIdleTimeout = Duration(seconds: 3);
  static const _typingPresenceTimeout = Duration(seconds: 6);
  static const _messageGroupWindow = Duration(minutes: 4);
  static const _readAckDebounce = Duration(milliseconds: 180);
  static const _pendingMessageMatchClockSkew = Duration(seconds: 5);
  static const _pendingMessageMatchWindow = Duration(seconds: 30);
  static const List<String> _composerEmojiOptions = [
    '😀',
    '😂',
    '😍',
    '🥹',
    '😎',
    '🤔',
    '😭',
    '😡',
    '👍',
    '👏',
    '🙏',
    '❤️',
    '🔥',
    '✨',
    '🎉',
    '🤝',
    '☕',
    '🍕',
    '🌞',
    '🌧️',
    '🎶',
    '📍',
    '👋',
    '💬',
  ];

  late final HttpService httpService;
  late final RoomMessagesCache roomMessagesCache;
  late final WebsocketService websocketService;
  late RoomSummary room;

  final List<ChatMessage> messages = [];
  final messageController = TextEditingController();
  late FocusNode messageFocusNode;
  final ScrollController _scrollController = ScrollController();

  StreamSubscription? messagesStreamSubscription;
  StreamSubscription? roomDeletedSubscription;
  StreamSubscription? connectionEventsSubscription;
  StreamSubscription? roomsChangedSubscription;
  StreamSubscription? roomRequestsChangedSubscription;
  StreamSubscription? typingStateSubscription;
  StreamSubscription? roomReadSubscription;

  bool _firstAutoscrollExecuted = false;
  bool _shouldAutoscroll = false;
  bool _roomClosed = false;
  bool _initialHistoryLoaded = false;
  List<RoomJoinRequest> pendingJoinRequests = [];
  final Set<int> _updatingJoinRequestUserIds = <int>{};
  final Map<int, _TypingParticipantState> _typingParticipants =
      <int, _TypingParticipantState>{};
  Timer? _typingIdleTimer;
  Timer? _typingPresenceCleanupTimer;
  Timer? _markReadTimer;
  bool _typingActive = false;
  bool _showEmojiPicker = false;
  int _pendingMessageSequence = 0;

  void _showRefreshFailure(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _persistMessagesCache() {
    roomMessagesCache.storeMessages(room.id, messages);
  }

  Map<int, RoomParticipant> get _participantsById => {
    for (final participant in room.participants) participant.id: participant,
  };

  bool get _isDirectRoom => !room.isGroup;

  bool _isAtConversationBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    return (_scrollController.position.maxScrollExtent -
                _scrollController.position.pixels)
            .abs() <=
        24;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          (_shouldAutoscroll || !_firstAutoscrollExecuted)) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _scrollListener() {
    _firstAutoscrollExecuted = true;
    _shouldAutoscroll = _isAtConversationBottom();
    if (_shouldAutoscroll) {
      _scheduleMarkRoomRead();
    }
  }

  void _handleComposerChanged() {
    if (_roomClosed) {
      return;
    }
    final hasText = messageController.text.trim().isNotEmpty;
    if (!hasText) {
      _typingIdleTimer?.cancel();
      unawaited(_setTypingState(false));
      return;
    }

    unawaited(_setTypingState(true));
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(_typingIdleTimeout, () {
      unawaited(_setTypingState(false));
    });
  }

  Future<void> _setTypingState(bool isTyping) async {
    if (_typingActive == isTyping || _roomClosed) {
      return;
    }
    _typingActive = isTyping;
    try {
      await websocketService.sendTypingState(room.id, isTyping: isTyping);
    } catch (_) {
      return;
    }
  }

  void _scheduleTypingPresenceCleanup() {
    _typingPresenceCleanupTimer?.cancel();
    if (_typingParticipants.isEmpty) {
      return;
    }
    _typingPresenceCleanupTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }
      final now = DateTime.now();
      final expiredUserIds = _typingParticipants.entries
          .where((entry) => entry.value.expiresAt.isBefore(now))
          .map((entry) => entry.key)
          .toList();
      if (expiredUserIds.isNotEmpty) {
        setState(() {
          for (final userId in expiredUserIds) {
            _typingParticipants.remove(userId);
          }
        });
      }
      _scheduleTypingPresenceCleanup();
    });
  }

  void _applyTypingStateEvent(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    if (userId == null || userId == widget.me.id) {
      return;
    }
    final participantJson = data['user'] as Map<String, dynamic>?;
    final participant = participantJson == null
        ? (_participantsById[userId] ??
              RoomParticipant(id: userId, username: 'Someone'))
        : RoomParticipant.fromJson(participantJson);
    final isTyping = data['is_typing'] == true;
    setState(() {
      if (!isTyping) {
        _typingParticipants.remove(userId);
      } else {
        _typingParticipants[userId] = _TypingParticipantState(
          participant: participant,
          expiresAt: DateTime.now().add(_typingPresenceTimeout),
        );
      }
    });
    _scheduleTypingPresenceCleanup();
  }

  void _scheduleMarkRoomRead({String? messageId}) {
    if (_roomClosed || messages.isEmpty) {
      return;
    }
    if (_firstAutoscrollExecuted && !_isAtConversationBottom()) {
      return;
    }
    _markReadTimer?.cancel();
    _markReadTimer = Timer(_readAckDebounce, () async {
      try {
        await httpService.mark_room_read(
          room.id,
          messageId: messageId ?? messages.first.id,
        );
      } on UnauthorizedResponse {
        if (!mounted || _roomClosed) {
          return;
        }
        _roomClosed = true;
        await expireSession(
          context,
          httpService: httpService,
          description: 'Your session has ended. Please sign in again.',
        );
      } catch (_) {}
    });
  }

  bool _messageHasReader(ChatMessage message, int userId) {
    return message.readByUsers.any((reader) => reader.id == userId);
  }

  void _applyRoomRead(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final messageId = data['message_id'] as String?;
    if (userId == null || messageId == null) {
      return;
    }
    final participant =
        _participantsById[userId] ??
        RoomParticipant(id: userId, username: 'Someone');
    var foundMarker = false;
    var changed = false;
    final updatedMessages = <ChatMessage>[];
    for (final message in messages) {
      if (!foundMarker && message.id == messageId) {
        foundMarker = true;
      }
      if (!foundMarker || _messageHasReader(message, userId)) {
        updatedMessages.add(message);
        continue;
      }
      changed = true;
      final readers = [...message.readByUsers, participant]
        ..sort((left, right) => left.username.compareTo(right.username));
      updatedMessages.add(message.copyWith(readByUsers: readers));
    }
    if (!changed || !mounted) {
      return;
    }
    setState(() {
      messages
        ..clear()
        ..addAll(updatedMessages);
      _persistMessagesCache();
    });
  }

  RoomParticipant _meParticipant() {
    final currentUserId = widget.me.id;
    if (currentUserId != null && _participantsById.containsKey(currentUserId)) {
      return _participantsById[currentUserId]!;
    }
    return RoomParticipant(
      id: currentUserId ?? 0,
      username: widget.me.username ?? 'You',
      picture: widget.me.picture,
    );
  }

  int _compareMessages(ChatMessage left, ChatMessage right) {
    final timestampComparison = right.timestamp.compareTo(left.timestamp);
    if (timestampComparison != 0) {
      return timestampComparison;
    }
    return right.id.compareTo(left.id);
  }

  ChatMessage _buildPendingOutgoingMessage(String body) {
    final clientTag =
        'pending-${DateTime.now().microsecondsSinceEpoch}-${_pendingMessageSequence++}';
    return ChatMessage(
      id: clientTag,
      clientTag: clientTag,
      body: body,
      senderId: widget.me.id ?? 0,
      senderUsername: widget.me.username,
      senderPicture: widget.me.picture,
      timestamp: DateTime.now().toUtc(),
      readByUsers: [_meParticipant()],
      deliveryState: MessageDeliveryState.sending,
    );
  }

  ChatMessage? _findPendingOutgoingMatch(ChatMessage incoming) {
    if (incoming.senderId != widget.me.id) {
      return null;
    }
    final candidates =
        messages
            .where(
              (message) =>
                  message.deliveryState == MessageDeliveryState.sending &&
                  message.senderId == incoming.senderId &&
                  message.body == incoming.body &&
                  !incoming.timestamp.isBefore(
                    message.timestamp.subtract(_pendingMessageMatchClockSkew),
                  ) &&
                  !incoming.timestamp.isAfter(
                    message.timestamp.add(_pendingMessageMatchWindow),
                  ),
            )
            .toList()
          ..sort((left, right) {
            final leftDifference = incoming.timestamp
                .difference(left.timestamp)
                .abs();
            final rightDifference = incoming.timestamp
                .difference(right.timestamp)
                .abs();
            final comparison = leftDifference.compareTo(rightDifference);
            if (comparison != 0) {
              return comparison;
            }
            return left.timestamp.compareTo(right.timestamp);
          });
    return candidates.isEmpty ? null : candidates.first;
  }

  void _replacePendingOutgoingMessage(
    String clientTag,
    ChatMessage sentMessage,
  ) {
    final pendingIndex = messages.indexWhere(
      (message) => message.clientTag == clientTag,
    );
    if (pendingIndex == -1) {
      _mergeMessages([sentMessage]);
      return;
    }
    messages[pendingIndex] = sentMessage;
    messages.sort(_compareMessages);
    _persistMessagesCache();
  }

  void _removePendingOutgoingMessage(String clientTag) {
    messages.removeWhere((message) => message.clientTag == clientTag);
    _persistMessagesCache();
  }

  ChatMessage _syncMessageParticipantMetadata(ChatMessage message) {
    final sender = _participantsById[message.senderId];
    final syncedReadByUsers = message.readByUsers
        .map((reader) => _participantsById[reader.id] ?? reader)
        .toList();
    if (sender == null &&
        syncedReadByUsers.length == message.readByUsers.length &&
        syncedReadByUsers.every(
          (reader) => message.readByUsers.any(
            (existing) =>
                existing.id == reader.id &&
                existing.username == reader.username &&
                existing.picture == reader.picture,
          ),
        )) {
      return message;
    }
    return message.copyWith(
      senderUsername: sender?.username ?? message.senderUsername,
      senderPicture: sender?.picture ?? message.senderPicture,
      readByUsers: syncedReadByUsers,
    );
  }

  void _resyncMessageParticipants() {
    if (messages.isEmpty) {
      return;
    }
    final existingMessages = List<ChatMessage>.from(messages);
    messages
      ..clear()
      ..addAll(existingMessages.map(_syncMessageParticipantMetadata));
    _persistMessagesCache();
  }

  String? _typingIndicatorLabel() {
    return describeTypingParticipants(
      _typingParticipants.values.map((state) => state.participant),
    );
  }

  Future<void> updateMessages({bool silentErrors = false}) async {
    try {
      final resp = await httpService.get_messages(
        room.id,
        silentErrors: silentErrors,
      );
      if (!mounted || _roomClosed) {
        return;
      }
      setState(() {
        _initialHistoryLoaded = true;
        _mergeMessages(resp);
        _resyncMessageParticipants();
        _scrollToBottom();
        _persistMessagesCache();
      });
      _scheduleMarkRoomRead();
    } on UnauthorizedResponse {
      if (!mounted || _roomClosed) {
        return;
      }
      _roomClosed = true;
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } on InvalidUsage catch (e) {
      if (e.code == 1000) {
        await _handleRoomDeleted();
      } else {
        rethrow;
      }
    } catch (_) {
      if (!mounted || _roomClosed) {
        return;
      }
      setState(() {
        _initialHistoryLoaded = true;
      });
      _showRefreshFailure('Could not refresh this room. Trying again soon.');
    }
  }

  Future<void> _refreshRoomSummary({bool silentErrors = false}) async {
    try {
      final rooms = await httpService.get_rooms(silentErrors: silentErrors);
      if (!mounted || _roomClosed) {
        return;
      }
      RoomSummary? updatedRoom;
      for (final candidate in rooms) {
        if (candidate.id == room.id) {
          updatedRoom = candidate;
          break;
        }
      }
      if (updatedRoom == null) {
        await _handleRoomDeleted();
        return;
      }
      setState(() {
        room = updatedRoom!;
        _resyncMessageParticipants();
      });
    } on UnauthorizedResponse {
      if (!mounted || _roomClosed) {
        return;
      }
      _roomClosed = true;
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } catch (_) {
      if (!mounted || _roomClosed) {
        return;
      }
      _showRefreshFailure('Could not refresh this room. Trying again soon.');
    }
  }

  Future<void> _refreshJoinRequests({bool silentErrors = false}) async {
    try {
      final requests = await httpService.get_room_requests(
        room.id,
        silentErrors: silentErrors,
      );
      if (!mounted || _roomClosed) {
        return;
      }
      setState(() {
        pendingJoinRequests = requests;
      });
    } on UnauthorizedResponse {
      if (!mounted || _roomClosed) {
        return;
      }
      _roomClosed = true;
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } on InvalidUsage catch (e) {
      if (e.code == 1000) {
        await _handleRoomDeleted();
      } else {
        rethrow;
      }
    } catch (_) {
      if (!mounted || _roomClosed) {
        return;
      }
      _showRefreshFailure(
        'Could not refresh join requests. Trying again soon.',
      );
    }
  }

  Future<void> _handleRoomDeleted() async {
    if (_roomClosed || !mounted) {
      return;
    }
    roomMessagesCache.clearRoom(room.id);
    _roomClosed = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This room is no longer available.')),
    );
    Navigator.pop(context, true);
  }

  Future<void> _handleSessionEnded() async {
    if (_roomClosed || !mounted) {
      return;
    }
    _roomClosed = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Your session has ended.')));
    Navigator.pop(context);
  }

  Future<void> _updatePushMuted(bool pushMuted) async {
    try {
      final updatedRoom = await httpService.update_room_settings(
        room.id,
        pushMuted: pushMuted,
      );
      if (!mounted || _roomClosed) {
        return;
      }
      setState(() {
        room = updatedRoom;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            pushMuted
                ? 'Notifications muted for this room.'
                : 'Notifications restored for this room.',
          ),
        ),
      );
    } on UnauthorizedResponse {
      if (_roomClosed || !mounted) {
        return;
      }
      _roomClosed = true;
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } on InvalidUsage catch (e) {
      if (e.code == 1000) {
        await _handleRoomDeleted();
      } else {
        rethrow;
      }
    } catch (error) {
      if (!mounted || _roomClosed) {
        return;
      }
      if (isAlreadyPresentedActionError(error)) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeActionError(
                error,
                fallbackDescription:
                    'Could not update notification settings right now.',
              ),
            ),
          ),
        );
    }
  }

  Future<void> _updateJoinRequest(
    RoomJoinRequest request, {
    required bool approve,
  }) async {
    final requesterId = request.user.id;
    if (_updatingJoinRequestUserIds.contains(requesterId)) {
      return;
    }
    setState(() {
      _updatingJoinRequestUserIds.add(requesterId);
    });
    try {
      if (approve) {
        final updatedRoom = await httpService.approve_room_request(
          room.id,
          requesterId,
        );
        if (!mounted || _roomClosed) {
          return;
        }
        setState(() {
          room = updatedRoom;
        });
      } else {
        await httpService.reject_room_request(room.id, requesterId);
      }
      if (!mounted || _roomClosed) {
        return;
      }
      await _refreshJoinRequests(silentErrors: true);
    } on UnauthorizedResponse {
      if (_roomClosed || !mounted) {
        return;
      }
      _roomClosed = true;
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } on InvalidUsage catch (e) {
      if (e.code == 1000) {
        await _handleRoomDeleted();
      } else {
        await _refreshJoinRequests(silentErrors: true);
      }
    } catch (error) {
      if (_roomClosed || !mounted) {
        return;
      }
      if (isAlreadyPresentedActionError(error)) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeActionError(
                error,
                fallbackDescription:
                    'Could not update that join request right now.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _updatingJoinRequestUserIds.remove(requesterId);
        });
      }
    }
  }

  Future<void> _leaveRoom() async {
    final userId = widget.me.id;
    final showLeaveInfo =
        !_isDirectRoom && userId != null && !hasSeenLeaveRoomInfo(userId);
    if (showLeaveInfo) {
      markLeaveRoomInfoSeen(userId);
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isDirectRoom ? 'Leave conversation?' : 'Leave room?'),
        content: Text(
          describeLeaveRoomDialogBody(
            isDirectRoom: _isDirectRoom,
            showNearbyHint: showLeaveInfo,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _roomClosed) {
      return;
    }

    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      await httpService.leave_room(room.id);
      if (!mounted) {
        return;
      }
      roomMessagesCache.clearRoom(room.id);
      _roomClosed = true;
      Navigator.pop(context, true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(_isDirectRoom ? 'Conversation left.' : 'Room left.'),
        ),
      );
    } on UnauthorizedResponse {
      if (_roomClosed || !mounted) {
        return;
      }
      _roomClosed = true;
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } on InvalidUsage catch (e) {
      if (e.code == 1000) {
        await _handleRoomDeleted();
      } else {
        rethrow;
      }
    } catch (error) {
      if (!mounted || _roomClosed) {
        return;
      }
      if (isAlreadyPresentedActionError(error)) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              describeActionError(
                error,
                fallbackDescription: _isDirectRoom
                    ? 'Could not leave this conversation right now.'
                    : 'Could not leave this room right now.',
              ),
            ),
          ),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    httpService =
        widget.httpService ?? Provider.of<HttpService>(context, listen: false);
    final providedRoomMessagesCache = Provider.of<RoomMessagesCache?>(
      context,
      listen: false,
    );
    roomMessagesCache =
        widget.roomMessagesCache ??
        providedRoomMessagesCache ??
        RoomMessagesCache();
    room = widget.room;
    final cachedMessages = roomMessagesCache.cachedMessagesFor(room.id);
    if (cachedMessages != null) {
      messages.addAll(cachedMessages);
      _initialHistoryLoaded = roomMessagesCache.hasLoadedRoom(room.id);
    }

    _scrollController.addListener(_scrollListener);
    messageFocusNode = FocusNode();
    messageFocusNode.addListener(() {
      if (messageFocusNode.hasFocus && _showEmojiPicker && mounted) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
      if (!messageFocusNode.hasFocus) {
        _typingIdleTimer?.cancel();
        unawaited(_setTypingState(false));
      }
    });
    messageController.addListener(_handleComposerChanged);
    _initializeRoom();
  }

  Future<void> _initializeRoom() async {
    messagesStreamSubscription = websocketService
        .messagesStream(widget.room.id)
        .listen((value) {
          if (!mounted || _roomClosed) {
            return;
          }
          setState(() {
            _mergeMessages(
              ChatMessage.listFromJson(
                value['data']['messages'] as List<dynamic>,
              ),
            );
            _resyncMessageParticipants();
            _scrollToBottom();
            _persistMessagesCache();
          });
          _scheduleMarkRoomRead();
        });
    typingStateSubscription = websocketService
        .typingStateStream(widget.room.id)
        .listen((value) {
          if (!mounted || _roomClosed) {
            return;
          }
          _applyTypingStateEvent(value['data'] as Map<String, dynamic>);
        });
    roomReadSubscription = websocketService
        .roomReadStream(widget.room.id)
        .listen((value) {
          if (!mounted || _roomClosed) {
            return;
          }
          _applyRoomRead(value['data'] as Map<String, dynamic>);
        });
    roomDeletedSubscription = websocketService
        .roomDeletedStream(widget.room.id)
        .listen((_) async {
          await _handleRoomDeleted();
        });
    roomRequestsChangedSubscription = websocketService
        .roomRequestsChangedStream(widget.room.id)
        .listen((_) {
          unawaited(_refreshJoinRequests(silentErrors: true));
        });
    roomsChangedSubscription = websocketService.roomsChangedStream().listen((
      _,
    ) {
      unawaited(_refreshRoomSummary(silentErrors: true));
    });
    connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) async {
      if (!mounted || _roomClosed) {
        return;
      }
      if (event == 'reconnected') {
        await _refreshRoomSummary(silentErrors: true);
        await _refreshJoinRequests(silentErrors: true);
        await updateMessages(silentErrors: true);
      } else if (event == 'signed-out') {
        await _handleSessionEnded();
      }
    });

    try {
      await websocketService.ensureConnected();
      if (!mounted || _roomClosed) {
        return;
      }

      await websocketService.subscribeRoom(room.id);
      await _refreshRoomSummary(silentErrors: true);
      await _refreshJoinRequests(silentErrors: true);
      await _ensureWarmMessages();
    } on RoomUnavailable {
      await _handleRoomDeleted();
    } catch (error) {
      if (!mounted || _roomClosed) {
        return;
      }
      _showRefreshFailure(
        describeActionError(
          error,
          fallbackDescription:
              'Could not connect to this room right now. Trying again soon.',
        ),
      );
    }
  }

  Future<void> _ensureWarmMessages() async {
    if (!roomMessagesCache.hasLoadedRoom(room.id)) {
      await updateMessages(silentErrors: true);
    }
  }

  void _mergeMessages(List<ChatMessage> incoming) {
    final mergedById = <String, ChatMessage>{};
    for (final message in messages) {
      mergedById[message.id] = message;
    }
    for (final message in incoming) {
      final pendingMatch = _findPendingOutgoingMatch(message);
      if (pendingMatch != null) {
        mergedById.remove(pendingMatch.id);
      }
      mergedById[message.id] = message;
    }
    final merged = mergedById.values.toList();
    merged.sort(_compareMessages);
    messages
      ..clear()
      ..addAll(merged);
  }

  String _roomSubtitle() {
    if (room.isGroup) {
      final otherCount = room.participants
          .where((participant) => participant.id != widget.me.id)
          .length;
      if (otherCount <= 0) {
        return 'Just you';
      }
      if (otherCount == 1) {
        return '1 other member';
      }
      return '$otherCount other members';
    }
    final other = room.otherParticipantFor(widget.me);
    if (other == null) {
      return 'Direct chat';
    }
    return 'Direct chat with ${other.username}';
  }

  Widget _buildAppBarTitle() {
    return Row(
      children: [
        AvatarImage(picture: room.displayPictureFor(widget.me), radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                room.displayTitleFor(widget.me),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                _roomSubtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _typingIdleTimer?.cancel();
    _typingPresenceCleanupTimer?.cancel();
    _markReadTimer?.cancel();
    unawaited(_setTypingState(false));
    websocketService.unsubscribeRoom(room.id);
    messagesStreamSubscription?.cancel();
    roomDeletedSubscription?.cancel();
    connectionEventsSubscription?.cancel();
    roomsChangedSubscription?.cancel();
    roomRequestsChangedSubscription?.cancel();
    typingStateSubscription?.cancel();
    roomReadSubscription?.cancel();
    _scrollController.removeListener(_scrollListener);
    messageController.removeListener(_handleComposerChanged);
    messageController.dispose();
    messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> sendMessage() async {
    final body = messageController.text;
    if (body.isNotEmpty) {
      final pendingMessage = _buildPendingOutgoingMessage(body);
      final pendingClientTag = pendingMessage.clientTag!;
      setState(() {
        _mergeMessages([pendingMessage]);
        _resyncMessageParticipants();
      });
      _scrollToBottom();
      messageController.text = '';
      _typingIdleTimer?.cancel();
      await _setTypingState(false);
      try {
        final sentMessage = await httpService.send_message(room.id, body);
        if (mounted && !_roomClosed) {
          setState(() {
            _replacePendingOutgoingMessage(pendingClientTag, sentMessage);
            _resyncMessageParticipants();
          });
          _scrollToBottom();
        }
        _scheduleMarkRoomRead(messageId: sentMessage.id);
      } on UnauthorizedResponse {
        if (mounted) {
          setState(() {
            _removePendingOutgoingMessage(pendingClientTag);
          });
        }
        if (_roomClosed || !mounted) {
          return;
        }
        _roomClosed = true;
        await expireSession(
          context,
          httpService: httpService,
          description: 'Your session has ended. Please sign in again.',
        );
      } on InvalidUsage catch (e) {
        if (mounted) {
          setState(() {
            _removePendingOutgoingMessage(pendingClientTag);
          });
        }
        if (e.code == 1000) {
          await _handleRoomDeleted();
        } else {
          rethrow;
        }
      } catch (error) {
        if (!mounted || _roomClosed) {
          return;
        }
        setState(() {
          _removePendingOutgoingMessage(pendingClientTag);
        });
        if (messageController.text.isEmpty) {
          messageController.value = TextEditingValue(
            text: body,
            selection: TextSelection.collapsed(offset: body.length),
          );
        }
        if (isAlreadyPresentedActionError(error)) {
          return;
        }
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                describeActionError(
                  error,
                  fallbackDescription: 'Could not send that message.',
                ),
              ),
            ),
          );
      }
    }
  }

  void _toggleComposerInputMode() {
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
      messageFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _showEmojiPicker = true;
    });
  }

  void _insertEmoji(String emoji) {
    final value = messageController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final replacementStart = start < 0 ? value.text.length : start;
    final replacementEnd = end < 0 ? value.text.length : end;
    final nextText = value.text.replaceRange(
      replacementStart,
      replacementEnd,
      emoji,
    );
    final caretOffset = replacementStart + emoji.length;
    messageController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: caretOffset),
      composing: TextRange.empty,
    );
  }

  bool _isSameConversationDay(ChatMessage left, ChatMessage right) {
    final leftLocal = left.timestamp.toLocal();
    final rightLocal = right.timestamp.toLocal();
    return leftLocal.year == rightLocal.year &&
        leftLocal.month == rightLocal.month &&
        leftLocal.day == rightLocal.day;
  }

  bool _isSameMessageCluster(ChatMessage left, ChatMessage right) {
    if (left.senderId != right.senderId) {
      return false;
    }
    return right.timestamp.difference(left.timestamp).abs() <=
        _messageGroupWindow;
  }

  BorderRadius _bubbleRadius({
    required bool isSender,
    required bool startsCluster,
    required bool endsCluster,
  }) {
    const full = Radius.circular(20);
    const small = Radius.circular(7);
    if (isSender) {
      return BorderRadius.only(
        topLeft: full,
        topRight: startsCluster ? full : small,
        bottomLeft: full,
        bottomRight: endsCluster ? small : full,
      );
    }
    return BorderRadius.only(
      topLeft: startsCluster ? full : small,
      topRight: full,
      bottomLeft: endsCluster ? small : full,
      bottomRight: full,
    );
  }

  String _formatMessageTime(DateTime timestamp) {
    final localizations = MaterialLocalizations.of(context);
    return localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(timestamp.toLocal()),
      alwaysUse24HourFormat: true,
    );
  }

  String _formatDayLabel(DateTime timestamp) {
    final localDate = timestamp.toLocal();
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${localDate.day} ${monthNames[localDate.month - 1]}';
  }

  Widget _buildPendingJoinRequestsCard() {
    if (pendingJoinRequests.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pending join requests',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              for (final request in pendingJoinRequests)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      AvatarImage(picture: request.user.picture, radius: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(request.user.username),
                            if (request.user.status?.isNotEmpty ?? false)
                              Text(
                                request.user.status!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed:
                            _updatingJoinRequestUserIds.contains(
                              request.user.id,
                            )
                            ? null
                            : () {
                                unawaited(
                                  _updateJoinRequest(request, approve: false),
                                );
                              },
                        child: const Text('Reject'),
                      ),
                      FilledButton(
                        onPressed:
                            _updatingJoinRequestUserIds.contains(
                              request.user.id,
                            )
                            ? null
                            : () {
                                unawaited(
                                  _updateJoinRequest(request, approve: true),
                                );
                              },
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final label = _typingIndicatorLabel();
    if (label == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _TypingDots(),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B4E52),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: DecoratedBox(
                      key: const Key('message-input-shell'),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            height: 56,
                            child: IconButton(
                              key: const Key('message-emoji-toggle-button'),
                              icon: Icon(
                                _showEmojiPicker
                                    ? Icons.keyboard_rounded
                                    : Icons.emoji_emotions_outlined,
                                color: const Color(0xFF61706E),
                              ),
                              onPressed: _toggleComposerInputMode,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              key: const Key('message-input-field'),
                              autofocus: true,
                              focusNode: messageFocusNode,
                              controller: messageController,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.send,
                              onTap: () {
                                if (_showEmojiPicker) {
                                  setState(() {
                                    _showEmojiPicker = false;
                                  });
                                }
                              },
                              onSubmitted: (v) async {
                                await sendMessage();
                                messageFocusNode.requestFocus();
                              },
                              decoration: const InputDecoration(
                                hintText: 'Type a message',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                  6,
                                  14,
                                  18,
                                  14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  key: const Key('message-send-shell'),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Semantics(
                    label: 'message-send',
                    button: true,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: IconButton(
                        key: const Key('message-send-button'),
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          await sendMessage();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_showEmojiPicker) ...[
              const SizedBox(height: 10),
              _EmojiPickerPanel(
                emojis: _composerEmojiOptions,
                onSelected: _insertEmoji,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (!_initialHistoryLoaded && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  size: 34,
                  color: Color(0xFF61706E),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No messages yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF31403E),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Start the conversation. New messages will appear here instantly.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5F6967),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final timelineMessages = messages.reversed.toList(growable: false);
    return ListView.builder(
      itemCount: timelineMessages.length,
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      itemBuilder: (context, index) {
        final message = timelineMessages[index];
        final previous = index > 0 ? timelineMessages[index - 1] : null;
        final next = index < timelineMessages.length - 1
            ? timelineMessages[index + 1]
            : null;
        final showDateDivider =
            previous == null || !_isSameConversationDay(previous, message);
        final startsCluster =
            previous == null || !_isSameMessageCluster(previous, message);
        final endsCluster =
            next == null || !_isSameMessageCluster(message, next);
        return Column(
          children: [
            if (showDateDivider)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 14, bottom: 12),
                child: _DayDivider(label: _formatDayLabel(message.timestamp)),
              ),
            _MessageBubbleRow(
              key: ValueKey('chat-message-${message.id}'),
              message: message,
              me: widget.me,
              isGroupRoom: room.isGroup,
              startsCluster: startsCluster,
              endsCluster: endsCluster,
              timeLabel: _formatMessageTime(message.timestamp),
              bubbleRadius: _bubbleRadius(
                isSender: message.senderId == widget.me.id,
                startsCluster: startsCluster,
                endsCluster: endsCluster,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8DED1),
      appBar: AppBar(
        title: _buildAppBarTitle(),
        actions: [
          InviteQrButton(room: room),
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'toggle-push',
                child: Text(
                  room.pushMuted
                      ? 'Turn on notifications'
                      : 'Mute notifications',
                ),
              ),
              PopupMenuItem<String>(
                value: 'leave-room',
                child: Text(
                  _isDirectRoom ? 'Leave conversation' : 'Leave room',
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'toggle-push') {
                unawaited(_updatePushMuted(!room.pushMuted));
              } else if (value == 'leave-room') {
                unawaited(_leaveRoom());
              }
            },
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4EBDD), Color(0xFFEBE1D2)],
          ),
        ),
        child: Column(
          children: [
            _buildPendingJoinRequestsCard(),
            Expanded(child: _buildMessageList()),
            _buildTypingIndicator(),
            _buildComposer(),
          ],
        ),
      ),
    );
  }
}

class _TypingParticipantState {
  const _TypingParticipantState({
    required this.participant,
    required this.expiresAt,
  });

  final RoomParticipant participant;
  final DateTime expiresAt;
}

class _EmojiPickerPanel extends StatelessWidget {
  const _EmojiPickerPanel({required this.emojis, required this.onSelected});

  final List<String> emojis;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('message-emoji-panel'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
          ),
          itemCount: emojis.length,
          itemBuilder: (context, index) {
            final emoji = emojis[index];
            return IconButton(
              key: Key('message-emoji-option-$index'),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: () => onSelected(emoji),
              icon: Text(emoji, style: const TextStyle(fontSize: 24)),
            );
          },
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF5D605E),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = ((_controller.value + (index * 0.18)) % 1);
            final opacity = 0.35 + (phase < 0.5 ? phase : 1 - phase) * 1.3;
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
              child: Opacity(
                opacity: opacity.clamp(0.2, 1.0),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF6A6D70),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 6, height: 6),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _MessageBubbleRow extends StatelessWidget {
  const _MessageBubbleRow({
    super.key,
    required this.message,
    required this.me,
    required this.isGroupRoom,
    required this.startsCluster,
    required this.endsCluster,
    required this.timeLabel,
    required this.bubbleRadius,
  });

  final ChatMessage message;
  final SessionUser me;
  final bool isGroupRoom;
  final bool startsCluster;
  final bool endsCluster;
  final String timeLabel;
  final BorderRadius bubbleRadius;

  @override
  Widget build(BuildContext context) {
    final isSender = message.senderId == me.id;
    final hasBeenRead = message.readByUsers.any(
      (reader) => reader.id != me.id && reader.id != message.senderId,
    );
    final bubbleColor = isSender
        ? const Color(0xFFDCF7C5)
        : Colors.white.withValues(alpha: 0.96);
    const textColor = Color(0xFF1F2528);
    final statusColor = isSender && hasBeenRead
        ? const Color(0xFF1D8F8C)
        : const Color(0xFF7A7E80);
    final statusIcon = message.deliveryState == MessageDeliveryState.sending
        ? Icons.done_rounded
        : Icons.done_all_rounded;

    return Padding(
      padding: EdgeInsets.only(
        top: startsCluster ? 6 : 2,
        bottom: endsCluster ? 6 : 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isSender
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isSender)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: endsCluster
                  ? AvatarImage(picture: message.senderPicture, radius: 15)
                  : const SizedBox(width: 30),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isSender
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isSender && isGroupRoom && startsCluster)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      message.senderUsername ?? 'Someone',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF35686A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: bubbleRadius,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          message.body,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: textColor, height: 1.25),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeLabel,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: const Color(0xFF7A7E80)),
                            ),
                            if (isSender) const SizedBox(width: 6),
                            if (isSender)
                              Icon(
                                key: const Key('message-status-icon'),
                                statusIcon,
                                size: 15,
                                color: statusColor,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
