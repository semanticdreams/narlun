import 'dart:async';

import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'invite_qr_button.dart';
import 'locator.dart';
import 'models.dart';
import 'session_actions.dart';
import 'websocket.dart';

class MessagesView extends StatefulWidget {
  final RoomSummary room;
  final SessionUser me;
  final HttpService? httpService;
  final WebsocketService? websocketService;

  const MessagesView({
    super.key,
    required this.room,
    required this.me,
    this.httpService,
    this.websocketService,
  });

  @override
  State<MessagesView> createState() => MessagesState();
}

class MessagesState extends State<MessagesView> {
  late final HttpService httpService;
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

  bool _firstAutoscrollExecuted = false;
  bool _shouldAutoscroll = false;
  bool _roomClosed = false;

  void _showRefreshFailure(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

    if (_scrollController.hasClients &&
        _scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent) {
      _shouldAutoscroll = true;
    } else {
      _shouldAutoscroll = false;
    }
  }

  Future<void> update_messages({bool silentErrors = false}) async {
    try {
      final resp = await httpService.get_messages(
        room.id,
        silentErrors: silentErrors,
      );
      if (!mounted || _roomClosed) {
        return;
      }
      setState(() {
        _mergeMessages(resp);
        _scrollToBottom();
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

  Future<void> _handleRoomDeleted() async {
    if (_roomClosed || !mounted) {
      return;
    }
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
    }
  }

  @override
  void initState() {
    super.initState();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    httpService =
        widget.httpService ??
        Provider.of<HttpService>(context, listen: false);
    room = widget.room;

    _scrollController.addListener(_scrollListener);
    messageFocusNode = FocusNode();
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
            _scrollToBottom();
          });
        });
    roomDeletedSubscription = websocketService
        .roomDeletedStream(widget.room.id)
        .listen((_) async {
          await _handleRoomDeleted();
        });
    roomsChangedSubscription = websocketService.roomsChangedStream().listen((_) {
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
        await update_messages(silentErrors: true);
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
      await update_messages(silentErrors: true);
    } on RoomUnavailable {
      await _handleRoomDeleted();
    } catch (_) {
      // The websocket service keeps retrying in the background.
    }
  }

  void _mergeMessages(List<ChatMessage> incoming) {
    final mergedById = <String, ChatMessage>{};
    for (final message in messages) {
      mergedById[message.id] = message;
    }
    for (final message in incoming) {
      mergedById[message.id] = message;
    }
    final merged = mergedById.values.toList();
    merged.sort((a, b) {
      final timestampComparison = b.timestamp.compareTo(a.timestamp);
      if (timestampComparison != 0) {
        return timestampComparison;
      }
      return b.id.compareTo(a.id);
    });
    messages
      ..clear()
      ..addAll(merged);
  }

  @override
  void dispose() {
    websocketService.unsubscribeRoom(room.id);
    messagesStreamSubscription?.cancel();
    roomDeletedSubscription?.cancel();
    connectionEventsSubscription?.cancel();
    roomsChangedSubscription?.cancel();
    _scrollController.removeListener(_scrollListener);
    messageController.dispose();
    messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> send_message() async {
    final body = messageController.text;
    if (body.isNotEmpty) {
      try {
        await httpService.send_message(room.id, body);
        messageController.text = '';
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.purple[50],
      appBar: AppBar(
        title: Text(room.displayTitleFor(widget.me)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toggle-push') {
                unawaited(_updatePushMuted(!room.pushMuted));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'toggle-push',
                child: Text(
                  room.pushMuted
                      ? 'Turn on notifications'
                      : 'Mute notifications',
                ),
              ),
            ],
          ),
          InviteQrButton(room: room),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              controller: _scrollController,
              itemBuilder: (BuildContext context, int index) {
                final msg = messages[(messages.length - 1) - index];
                final isSender = msg.senderId == widget.me.id;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: BubbleSpecialOne(
                    text: msg.body,
                    isSender: isSender,
                    tail: true,
                    color: isSender ? Colors.purple[500]! : Colors.grey[700]!,
                    textStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('message-input-field'),
                    autofocus: true,
                    focusNode: messageFocusNode,
                    controller: messageController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) async {
                      await send_message();
                      messageFocusNode.requestFocus();
                    },
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Semantics(
                    label: 'message-send',
                    button: true,
                    child: IconButton(
                      key: const Key('message-send-button'),
                      icon: Icon(
                        Icons.send,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      onPressed: () async {
                        await send_message();
                      },
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
