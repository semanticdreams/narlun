import 'package:flutter/material.dart';
import 'navdrawer.dart';
import 'appbar_avatar.dart';
import 'nearby_users_view.dart';
import 'conversations_view.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            drawer: NavDrawer(),
            appBar: AppBar(
              title: const Text('Narlun'),
              actions: const [AppBarAvatar()],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.people)),
                  Tab(icon: Icon(Icons.message)),
                  //Tab(icon: Icon(Icons.qr_code_2)),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                NearbyUsersView(
                  onUserJoined: (_) {
                    DefaultTabController.of(context).animateTo(1);
                  },
                ),
                const ConversationsView(),
              ],
            ),
          );
        },
      ),
    );
  }
}
