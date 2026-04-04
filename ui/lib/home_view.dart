import 'package:flutter/material.dart';

import 'appbar_avatar.dart';
import 'conversations_view.dart';
import 'location_service.dart';
import 'navdrawer.dart';
import 'nearby_users_view.dart';

class HomeView extends StatelessWidget {
  final int initialTabIndex;
  final LocationService? nearbyLocationService;
  final Widget? roomsView;

  const HomeView({
    super.key,
    this.initialTabIndex = 1,
    this.nearbyLocationService,
    this.roomsView,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex,
      child: _HomeScaffold(
        nearbyLocationService: nearbyLocationService,
        roomsView: roomsView,
      ),
    );
  }
}

class _HomeScaffold extends StatefulWidget {
  final LocationService? nearbyLocationService;
  final Widget? roomsView;

  const _HomeScaffold({
    required this.nearbyLocationService,
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
  }

  @override
  Widget build(BuildContext context) {
    final tabController = _tabController ?? DefaultTabController.of(context);
    return Scaffold(
      drawer: NavDrawer(),
      appBar: AppBar(
        title: const Text('Narlun'),
        actions: const [AppBarAvatar()],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.people)),
            Tab(icon: Icon(Icons.message)),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          NearbyUsersView(
            autoCheckin: _activeTabIndex == 0,
            locationService: widget.nearbyLocationService,
            onUserJoined: (_) {
              tabController.animateTo(1);
            },
          ),
          widget.roomsView ?? const ConversationsView(),
        ],
      ),
    );
  }
}
