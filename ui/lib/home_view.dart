import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'appbar_avatar.dart';
import 'conversations_view.dart';
import 'home_tab_storage.dart';
import 'invite_qr_button.dart';
import 'location_service.dart';
import 'messages_view.dart';
import 'me_model.dart';
import 'models.dart';
import 'narlun_app_bar_title.dart';
import 'nearby_users_view.dart';

class HomeView extends StatelessWidget {
  final int? initialTabIndex;
  final int? initialRoomIdToOpen;
  final LocationService? nearbyLocationService;
  final Widget? roomsView;

  const HomeView({
    super.key,
    this.initialTabIndex,
    this.initialRoomIdToOpen,
    this.nearbyLocationService,
    this.roomsView,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedInitialTabIndex =
        initialTabIndex ?? readStoredHomeTabIndex() ?? 0;
    return DefaultTabController(
      length: 2,
      initialIndex: resolvedInitialTabIndex,
      child: _HomeScaffold(
        nearbyLocationService: nearbyLocationService,
        initialRoomIdToOpen: initialRoomIdToOpen,
        roomsView: roomsView,
      ),
    );
  }
}

class _HomeScaffold extends StatefulWidget {
  final LocationService? nearbyLocationService;
  final int? initialRoomIdToOpen;
  final Widget? roomsView;

  const _HomeScaffold({
    required this.nearbyLocationService,
    required this.initialRoomIdToOpen,
    required this.roomsView,
  });

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> {
  TabController? _tabController;
  int _activeTabIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (_tabController == controller) {
      return;
    }
    _tabController?.removeListener(_handleTabChanged);
    _tabController = controller;
    _activeTabIndex = controller.index;
    writeStoredHomeTabIndex(controller.index);
    _tabController?.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChanged);
    super.dispose();
  }

  void _handleTabChanged() {
    final controller = _tabController;
    if (controller == null || controller.indexIsChanging) {
      return;
    }
    if (_activeTabIndex == controller.index || !mounted) {
      return;
    }
    setState(() {
      _activeTabIndex = controller.index;
    });
    writeStoredHomeTabIndex(controller.index);
  }

  Future<void> _openNearbyRoom(NearbyUser user, int roomId) async {
    final me = Provider.of<MeModel>(context, listen: false).data;
    if (me == null || !me.authenticated || me.id == null) {
      return;
    }

    _tabController?.animateTo(1);
    final room = RoomSummary(
      id: roomId,
      isGroup: false,
      updatedAt: DateTime.now(),
      participants: [
        RoomParticipant(id: me.id!, username: me.username ?? ''),
        RoomParticipant(
          id: user.id,
          username: user.username,
          picture: user.picture,
        ),
      ],
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessagesView(room: room, me: me),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabController = _tabController ?? DefaultTabController.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const NarlunAppBarTitle(),
        actions: const [InviteQrButton(), AppBarAvatar()],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.people_outline), text: 'Nearby'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Rooms'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          NearbyUsersView(
            autoCheckin: _activeTabIndex == 0,
            locationService: widget.nearbyLocationService,
            onUserJoined: _openNearbyRoom,
          ),
          widget.roomsView ??
              ConversationsView(
                initialRoomIdToOpen: widget.initialRoomIdToOpen,
                showChrome: false,
                onOpenNearby: () {
                  tabController.animateTo(0);
                },
              ),
        ],
      ),
    );
  }
}
