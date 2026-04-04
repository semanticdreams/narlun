import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'avatar_image.dart';
import 'dialog_service.dart';
import 'http.dart';
import 'location_service.dart';
import 'locator.dart';
import 'me_model.dart';
import 'models.dart';
import 'session_actions.dart';

class NearbyUsersView extends StatefulWidget {
  final FutureOr<void> Function(NearbyUser user, int roomId) onUserJoined;
  final HttpService? httpService;
  final DialogService? dialogService;
  final LocationService? locationService;
  final bool autoCheckin;

  const NearbyUsersView({
    super.key,
    required this.onUserJoined,
    this.httpService,
    this.dialogService,
    this.locationService,
    this.autoCheckin = true,
  });

  @override
  State<NearbyUsersView> createState() => _NearbyUsersState();
}

class _NearbyUsersState extends State<NearbyUsersView> {
  late final HttpService httpService;
  late final DialogService dialogService;
  late final LocationService locationService;

  final List<NearbyUser> nearbyUsers = [];
  bool _loading = false;
  String _statusMessage = 'Checking your location...';
  bool _didInitialCheckin = false;

  @override
  void initState() {
    super.initState();
    httpService =
        widget.httpService ?? Provider.of<HttpService>(context, listen: false);
    dialogService = widget.dialogService ?? locator<DialogService>();
    locationService = widget.locationService ?? GeolocatorLocationService();
    _maybeStartInitialCheckin();
  }

  @override
  void didUpdateWidget(covariant NearbyUsersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartInitialCheckin();
  }

  void _maybeStartInitialCheckin() {
    if (!widget.autoCheckin || _didInitialCheckin) {
      return;
    }
    _didInitialCheckin = true;
    unawaited(checkin());
  }

  void _setStatus(String status, {required bool loading}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = loading;
      _statusMessage = status;
    });
  }

  Future<void> _showLocationProblem(String description) async {
    _setStatus(description, loading: false);
    await dialogService.showDialog(
      title: 'Location needed',
      description: description,
    );
  }

  Future<void> checkin() async {
    final me = Provider.of<MeModel>(context, listen: false);
    if (me.data == null || !me.data!.authenticated) {
      return;
    }
    _setStatus('Checking your location...', loading: true);

    if (!(await locationService.isLocationServiceEnabled())) {
      nearbyUsers.clear();
      await _showLocationProblem('Location services are not enabled.');
      return;
    }

    var permission = await locationService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await locationService.requestPermission();
      if (permission == LocationPermission.denied) {
        nearbyUsers.clear();
        await _showLocationProblem('Location access was denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      nearbyUsers.clear();
      await _showLocationProblem(
        'Location access is permanently denied in this browser.',
      );
      return;
    }

    try {
      final loc = await locationService.getCurrentPosition();
      final resp = await httpService.checkin(loc.latitude, loc.longitude);
      if (!mounted) {
        return;
      }
      setState(() {
        nearbyUsers
          ..clear()
          ..addAll(resp);
        _loading = false;
        _statusMessage = nearbyUsers.isEmpty
            ? 'Nobody nearby right now. Pull to refresh again soon.'
            : 'Tap someone to open a room.';
      });
    } on UnauthorizedResponse {
      if (!mounted) {
        return;
      }
      await expireSession(
        context,
        httpService: httpService,
        description: 'Your session has ended. Please sign in again.',
      );
    } catch (_) {
      nearbyUsers.clear();
      _setStatus('Could not refresh nearby people. Pull to try again.', loading: false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not refresh nearby people.')),
      );
    }
  }

  Future<void> joinUser(NearbyUser user) async {
    final roomId = await httpService.join_user(user.id);
    await Future.sync(() => widget.onUserJoined(user, roomId));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: checkin,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
          ),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    if (_loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_loading) const SizedBox(width: 12),
                    Expanded(child: Text(_statusMessage)),
                  ],
                ),
              ),
              for (final user in nearbyUsers)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ListTile(
                    key: ValueKey('nearby-user-${user.id}'),
                    leading: AvatarImage(picture: user.picture),
                    title: Text(user.username),
                    subtitle: (user.status?.isNotEmpty ?? false)
                        ? Text(
                            user.status!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${user.distance}m away',
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'last seen ${timeago.format(user.lastSeen)}',
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                    onTap: () async {
                      await joinUser(user);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
