import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:url_strategy/url_strategy.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:json_theme/json_theme.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:chat_bubbles/chat_bubbles.dart';

import 'http.dart';
import 'locator.dart';
import 'websocket.dart';

WebsocketService _websocketService = locator<WebsocketService>();

class MessagesView extends StatefulWidget {
  final room;
  final me;

  const MessagesView({Key? key, this.room, this.me}) : super(key: key);

  @override
  MessagesState createState() {
    return MessagesState();
  }
}

class MessagesState extends State<MessagesView> {
  final HttpService httpService = HttpService();

  final messages = [];

  final messageController = TextEditingController();
  late FocusNode messageFocusNode;

  final ScrollController _scrollController = ScrollController();

  late final messagesStreamSubscription;

  bool _firstAutoscrollExecuted = false;
  bool _shouldAutoscroll = false;

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
    final resp = await httpService.get_messages(widget.room['id']);
    setState(() {
      messages.clear();
      messages.addAll(resp);
      _scrollToBottom();
    });
  }

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_scrollListener);

    update_messages();

    messagesStreamSubscription =
        _websocketService.messagesStream(widget.room['id']).listen((value) {
      setState(() {
        // TODO are new messages in right order?
        messages.insertAll(0, value['data']['messages']);
        _scrollToBottom();
      });
    });
    _websocketService.subscribe_room(widget.room['id']);

    messageFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _websocketService.unsubscribe_room(widget.room['id']);
    messagesStreamSubscription.cancel();
    _scrollController.removeListener(_scrollListener);
    messageController.dispose();
    messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future send_message() async {
    final body = messageController.text;
    if (!body.isEmpty) {
      await httpService.send_message(widget.room['id'], body);
      //await update_messages();
      messageController.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.purple[50],
        appBar: AppBar(
          title: Text(widget.room['is_group']
              ? widget.room['name']
              : widget.room['participants'].singleWhere(
                  (x) => x['id'] != widget.me.data['id'])['username']),
          actions: [],
        ),
        body: Column(children: [
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
                            color: is_sender
                                ? Colors.purple[500]!
                                : Colors.grey[700]!,
                            textStyle: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onPrimary)));
                  })),
          //Spacer(),
//          TextField(),
          Container(
              padding: const EdgeInsets.all(4.0),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
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
                            border: OutlineInputBorder()))),
                SizedBox(width: 4),
                CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: IconButton(
                        icon: Icon(Icons.send,
                            color: Theme.of(context).colorScheme.onPrimary),
                        onPressed: () async {
                          await send_message();
                        })),
              ]))
        ]));
  }
}
