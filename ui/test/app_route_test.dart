import 'package:flutter_test/flutter_test.dart';
import 'package:narlun/models.dart';
import 'package:narlun/route_utils.dart';

void main() {
  test('keeps welcome route when session state is still unknown', () {
    expect(resolveStartupLocation(Uri.parse('/'), null), '/');
    expect(
      resolveStartupLocation(Uri.parse('/rooms?open_room=7'), null),
      '/?next=%2Frooms%3Fopen_room%3D7',
    );
  });

  test('routes authenticated startup directly into the app', () {
    const me = SessionUser(authenticated: true, id: 7, username: 'sam');

    expect(resolveStartupLocation(Uri.parse('/'), me), '/home');
    expect(
      resolveStartupLocation(Uri.parse('/?next=%2Finvite%2Fabc123'), me),
      '/invite/abc123',
    );
    expect(resolveStartupLocation(Uri.parse('/signin'), me), '/home');
    expect(resolveStartupLocation(Uri.parse('/?next=%2Fsignin'), me), '/home');
  });

  test('routes unauthenticated startup straight to signup', () {
    final me = SessionUser.unauthenticated();

    expect(resolveStartupLocation(Uri.parse('/'), me), '/signup');
    expect(
      resolveStartupLocation(Uri.parse('/?next=%2Frooms%3Fopen_room%3D7'), me),
      '/signup?next=%2Frooms%3Fopen_room%3D7',
    );
    expect(
      resolveStartupLocation(Uri.parse('/profile'), me),
      '/signup?next=%2Fprofile',
    );
    expect(resolveStartupLocation(Uri.parse('/signup'), me), '/signup');
  });

  test('builds stable web routes for tabs, rooms, and invites', () {
    expect(nearbyRoute(), '/nearby');
    expect(roomsRoute(), '/rooms');
    expect(roomsRouteWithOpenRoom(42), '/rooms?open_room=42');
    expect(inviteQrRoute(), '/invite');
    expect(inviteQrRoute(roomId: 7), '/invite?room_id=7');
  });
}
