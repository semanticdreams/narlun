import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'avatar_image.dart';
import 'http.dart';
import 'me_model.dart';
import 'messages_view.dart';
import 'appbar_avatar.dart';
import 'locator.dart';
import 'websocket.dart';

class ConversationsView extends StatefulWidget {
  final HttpService? httpService;
  final WebsocketService? websocketService;

  const ConversationsView({Key? key, this.httpService, this.websocketService})
    : super(key: key);

  @override
  _ConversationsState createState() => _ConversationsState();
}

class _ConversationsState extends State<ConversationsView> {
  late final WebsocketService websocketService;
  late final HttpService httpService;

  final rooms = [];
  StreamSubscription? roomsChangedSubscription;
  StreamSubscription? connectionEventsSubscription;

  Future update_rooms() async {
    final resp = await httpService.get_rooms();
    if (!mounted) {
      return;
    }
    setState(() {
      rooms.clear();
      rooms.addAll(resp);
    });
  }

  @override
  void initState() {
    super.initState();
    websocketService = widget.websocketService ?? locator<WebsocketService>();
    httpService =
        widget.httpService ?? HttpService(websocketService: websocketService);
    update_rooms();
    unawaited(websocketService.ensureConnected());
    roomsChangedSubscription = websocketService.roomsChangedStream().listen(
      (_) => update_rooms(),
    );
    connectionEventsSubscription = websocketService.connectionEvents.listen((
      event,
    ) {
      if (event == 'reconnected') {
        update_rooms();
      }
    });
  }

  @override
  void dispose() {
    roomsChangedSubscription?.cancel();
    connectionEventsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rooms'), actions: [AppBarAvatar()]),
      body: Consumer<MeModel>(
        builder: (context, me, child) {
          return ListView(
            children: [
              for (var room in rooms)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ListTile(
                    leading: AvatarImage(
                      picture: room['is_group'] || !me.data!['authenticated']
                          ? room['picture']
                          : room['participants'].singleWhere(
                              (x) => x['id'] != me.data!['id'],
                            )['picture'],
                    ),
                    trailing: Text(
                      timeago.format(DateTime.parse(room['updated_at'])),
                    ),
                    title: Text(
                      room['is_group'] || !me.data!['authenticated']
                          ? (room['name'] ?? '')
                          : room['participants'].singleWhere(
                              (x) => x['id'] != me.data!['id'],
                            )['username'],
                    ),
                    subtitle: Text(
                      room['last_message'] != null
                          ? room['last_message']['body']
                          : '',
                    ),
                    onTap: () async {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              MessagesView(room: room, me: me),
                        ),
                      );
                    },
                  ),
                ), // TODO subtitle should be different for group, needs name
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add your onPressed code here!
        },
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }
}
