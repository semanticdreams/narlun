import 'dart:async';

import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:flutter/material.dart';

import 'http.dart';
import 'locator.dart';
import 'websocket.dart';

class MessagesView extends StatefulWidget {
  final room;
  final me;
  final HttpService? httpService;
  final WebsocketService? websocketService;

  const MessagesView({
    Key? key,
    this.room,
    this.me,
    this.httpService,
    this.websocketService,
  }) : super(key: key);

  @override
  MessagesState createState() {
    return MessagesState();
  }
}

class MessagesState extends State<MessagesView> {
  late final HttpService httpService;
  late final WebsocketService websocketService;

  final messages = [];

  final messageController = TextEditingController();
  late FocusNode messageFocusNode;

  final ScrollController _scrollController = ScrollController();

  StreamSubscription? messagesStreamSubscription;
  StreamSubscription? roomDeletedSubscription;
  StreamSubscription? connectionEventsSubscription;

  bool _firstAutoscrollExecuted = false;
  bool _shouldAutoscroll = false;
  bool _roomClosed = false;

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

  Future update_messages() async {
    try {
      final resp = await httpService.get_messages(widget.room['id']);
      if (!mounted || _roomClosed) {
        return;
      }
      setState(() {
        _mergeMessages(resp);
        _scrollToBottom();
      });
    } on InvalidUsage catch (e) {
      if (e.code == 1000) {
        await _handleRoomDeleted();
      } else {
        rethrow;
      }
    }
  }

  Future _handleRoomDeleted() async {
    if (_roomClosed || !mounted) {
      return;
    }
    _roomClosed = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This room is no longer available.')),
    );
    Navigator.pop(context);
  }

  Future _handleSessionEnded() async {
    if (_roomClosed || !mounted) {
      return;
    }
    _roomClosed = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Your session has ended.')));
    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    httpService =
        widget.httpService ?? HttpService(websocketService: websocketService);

    _scrollController.addListener(_scrollListener);

    _initializeRoom();

    messageFocusNode = FocusNode();
  }

  Future<void> _initializeRoom() async {
    messagesStreamSubscription = websocketService
        .messagesStream(widget.room['id'])
        .listen((value) {
          if (!mounted || _roomClosed) {
            return;
          }
          setState(() {
            _mergeMessages(value['data']['messages']);
            _scrollToBottom();
          });
        });
    roomDeletedSubscription = websocketService
        .roomDeletedStream(widget.room['id'])
        .listen((_) async {
          await _handleRoomDeleted();
        });
    connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) async {
      if (!mounted || _roomClosed) {
        return;
      }
      if (event == 'reconnected') {
        await update_messages();
      } else if (event == 'signed-out') {
        await _handleSessionEnded();
      }
    });

    try {
      await websocketService.ensureConnected();
      if (!mounted || _roomClosed) {
        return;
      }

      await websocketService.subscribeRoom(widget.room['id']);
      await update_messages();
    } on RoomUnavailable {
      await _handleRoomDeleted();
    } catch (_) {
      // The websocket service keeps retrying in the background.
    }
  }

  void _mergeMessages(List<dynamic> incoming) {
    final mergedById = <String, dynamic>{};
    for (final message in messages) {
      final messageId = message['id'];
      if (messageId != null) {
        mergedById['$messageId'] = message;
      }
    }
    for (final message in incoming) {
      final messageId = message['id'];
      if (messageId != null) {
        mergedById['$messageId'] = message;
      }
    }
    final merged = mergedById.values.toList();
    merged.sort((a, b) {
      final timestampComparison = '${b['timestamp']}'.compareTo(
        '${a['timestamp']}',
      );
      if (timestampComparison != 0) {
        return timestampComparison;
      }
      return '${b['id']}'.compareTo('${a['id']}');
    });
    messages
      ..clear()
      ..addAll(merged);
  }

  @override
  void dispose() {
    websocketService.unsubscribeRoom(widget.room['id']);
    messagesStreamSubscription?.cancel();
    roomDeletedSubscription?.cancel();
    connectionEventsSubscription?.cancel();
    _scrollController.removeListener(_scrollListener);
    messageController.dispose();
    messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future send_message() async {
    final body = messageController.text;
    if (!body.isEmpty) {
      try {
        await httpService.send_message(widget.room['id'], body);
        messageController.text = '';
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
        title: Text(
          widget.room['is_group']
              ? widget.room['name']
              : widget.room['participants'].singleWhere(
                  (x) => x['id'] != widget.me.data['id'],
                )['username'],
        ),
        actions: [],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              //reverse: true,
              itemCount: messages.length,
              controller: _scrollController,
              itemBuilder: (BuildContext context, int index) {
                final msg = messages[(messages.length - 1) - index];
                final is_sender = msg['sender_id'] == widget.me.data['id'];
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 1),
                  child: BubbleSpecialOne(
                    text: msg['body'],
                    isSender: is_sender,
                    tail: true,
                    color: is_sender ? Colors.purple[500]! : Colors.grey[700]!,
                    textStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                );
              },
            ),
          ),
          //Spacer(),
          //          TextField(),
          Container(
            padding: const EdgeInsets.all(4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    focusNode: messageFocusNode,
                    controller: messageController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) async {
                      await send_message();
                      messageFocusNode.requestFocus();
                    },
                    decoration: InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 4),
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: IconButton(
                    icon: Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    onPressed: () async {
                      await send_message();
                    },
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
