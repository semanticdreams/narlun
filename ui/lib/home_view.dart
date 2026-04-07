import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'appbar_avatar.dart';
import 'conversations_view.dart';
import 'home_tab_storage.dart';
import 'http.dart';
import 'invite_qr_button.dart';
import 'location_service.dart';
import 'messages_view.dart';
import 'me_model.dart';
import 'models.dart';
import 'nearby_feed_model.dart';
import 'narlun_app_bar_title.dart';
import 'nearby_users_view.dart';
import 'rooms_feed_model.dart';
import 'route_utils.dart';

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
  MeModel? _meModel;
  late final NearbyFeedModel _nearbyFeedModel;
  late final RoomsFeedModel _roomsFeedModel;
  bool _ownsNearbyFeedModel = false;
  bool _ownsRoomsFeedModel = false;

  @override
  void initState() {
    super.initState();
    final httpService = Provider.of<HttpService>(context, listen: false);
    final providedNearbyFeedModel = Provider.of<NearbyFeedModel?>(
      context,
      listen: false,
    );
    final providedRoomsFeedModel = Provider.of<RoomsFeedModel?>(
      context,
      listen: false,
    );
    _nearbyFeedModel =
        providedNearbyFeedModel ??
        NearbyFeedModel(
          httpService: httpService,
          locationService:
              widget.nearbyLocationService ?? createLocationService(),
        );
    _roomsFeedModel =
        providedRoomsFeedModel ?? RoomsFeedModel(httpService: httpService);
    _ownsNearbyFeedModel = providedNearbyFeedModel == null;
    _ownsRoomsFeedModel = providedRoomsFeedModel == null;
    final meModel = Provider.of<MeModel>(context, listen: false);
    _meModel = meModel;
    _meModel?.addListener(_handleSessionChanged);
    _syncFeedSessions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final meModel = Provider.of<MeModel>(context);
    if (!identical(_meModel, meModel)) {
      _meModel?.removeListener(_handleSessionChanged);
      _meModel = meModel;
      _meModel?.addListener(_handleSessionChanged);
      _syncFeedSessions();
    }
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
    _meModel?.removeListener(_handleSessionChanged);
    if (_ownsNearbyFeedModel) {
      _nearbyFeedModel.dispose();
    }
    if (_ownsRoomsFeedModel) {
      _roomsFeedModel.dispose();
    }
    super.dispose();
  }

  void _handleSessionChanged() {
    _syncFeedSessions();
  }

  void _syncFeedSessions() {
    final session = _meModel?.data;
    _nearbyFeedModel.syncSession(session);
    _roomsFeedModel.syncSession(session);
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

    final currentUri = currentRouteUri(context);
    if (currentUri == null) {
      return;
    }
    if (!const {'/home', '/nearby', '/rooms'}.contains(currentUri.path)) {
      return;
    }
    final targetRoute = controller.index == 0 ? nearbyRoute() : roomsRoute();
    final alreadyShowingTarget =
        currentUri.path == Uri.parse(targetRoute).path &&
        (currentUri.path != '/rooms' || roomToOpenFromContext(context) == null);
    if (!alreadyShowingTarget) {
      Navigator.of(context).pushReplacement(_buildShellRoute(targetRoute));
    }
  }

  Route<void> _buildShellRoute(String routeName) {
    final initialTabIndex = Uri.parse(routeName).path == '/nearby' ? 0 : 1;
    return PageRouteBuilder<void>(
      settings: RouteSettings(name: routeName),
      pageBuilder: (context, animation, secondaryAnimation) => HomeView(
        initialTabIndex: initialTabIndex,
        nearbyLocationService: widget.nearbyLocationService,
        roomsView: widget.roomsView,
      ),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  Future<void> _openNearbyRoom(NearbyUser user, int roomId) async {
    final me = Provider.of<MeModel>(context, listen: false).data;
    if (me == null || !me.authenticated || me.id == null) {
      return;
    }

    final room = RoomSummary(
      id: roomId,
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
        settings: RouteSettings(name: roomsRouteWithOpenRoom(roomId)),
        builder: (context) => MessagesView(room: room, me: me),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabController = _tabController ?? DefaultTabController.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
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
            nearbyFeedModel: _nearbyFeedModel,
            onUserJoined: _openNearbyRoom,
          ),
          widget.roomsView ??
              ConversationsView(
                initialRoomIdToOpen: widget.initialRoomIdToOpen,
                roomsFeedModel: _roomsFeedModel,
                enableRealtimeRoomSummarySync: false,
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
