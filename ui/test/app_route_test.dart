import 'package:flutter_test/flutter_test.dart';
import 'package:narlun/models.dart';
import 'package:narlun/route_utils.dart';
import 'package:narlun/set_page_title.dart';

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
    expect(isPrimaryAppShellRoute(Uri.parse('/home')), isTrue);
    expect(isPrimaryAppShellRoute(Uri.parse('/nearby')), isTrue);
    expect(isPrimaryAppShellRoute(Uri.parse('/rooms')), isTrue);
    expect(isPrimaryAppShellRoute(Uri.parse('/rooms?open_room=42')), isTrue);
    expect(
      shouldShowPersistentInstallSuggestionForRoute(Uri.parse('/')),
      isFalse,
    );
    expect(
      shouldShowPersistentInstallSuggestionForRoute(
        Uri.parse('/invite/token-123'),
      ),
      isFalse,
    );
    expect(
      shouldShowPersistentInstallSuggestionForRoute(Uri.parse('/rooms')),
      isTrue,
    );
    expect(isPrimaryAppShellRoute(Uri.parse('/profile')), isFalse);
    expect(
      sanitizeInviteBackToRoute('/rooms?open_room=42'),
      '/rooms?open_room=42',
    );
    expect(sanitizeInviteBackToRoute('/profile'), '/profile');
    expect(sanitizeInviteBackToRoute('/invite?room_id=7'), isNull);
    expect(sanitizeInviteBackToRoute('/invite/token-123'), isNull);
    expect(sanitizeInviteBackToRoute('/'), isNull);
    expect(sanitizeInviteBackToRoute('not a route'), isNull);
    expect(sanitizeStandaloneBackRoute('/'), '/');
    expect(sanitizeStandaloneBackRoute('/settings'), '/settings');
    expect(
      sanitizeStandaloneBackRoute('/invite/token-123'),
      '/invite/token-123',
    );
    expect(sanitizeStandaloneBackRoute('not a route'), isNull);
    expect(inviteQrRoute(), '/invite');
    expect(inviteQrRoute(roomId: 7), '/invite?room_id=7');
    expect(
      inviteQrRouteWithBackTo(roomId: 7, backTo: '/rooms?open_room=7'),
      '/invite?room_id=7&back_to=%2Frooms%3Fopen_room%3D7',
    );
  });

  test('resolves standalone back fallback routes', () {
    expect(
      standaloneBackFallbackRoute(
        currentRouteName: '/profile',
        previousRouteName: '/rooms',
      ),
      '/rooms',
    );
    expect(
      standaloneBackFallbackRoute(currentRouteName: '/settings'),
      '/profile',
    );
    expect(
      standaloneBackFallbackRoute(
        currentRouteName: '/invite?room_id=42&back_to=%2Frooms',
      ),
      '/rooms',
    );
    expect(
      standaloneBackFallbackRoute(currentRouteName: '/rooms?open_room=42'),
      '/rooms',
    );
    expect(standaloneBackFallbackRoute(currentRouteName: '/nearby'), '/home');
    expect(
      standaloneBackFallbackRoute(
        currentRouteName: '/invite/token-123',
        me: const SessionUser(authenticated: true, id: 7, username: 'sam'),
      ),
      '/home',
    );
    expect(
      standaloneBackFallbackRoute(
        currentRouteName: '/invite/token-123',
        me: SessionUser.unauthenticated(),
      ),
      '/signup',
    );
  });

  test('describes user-facing page titles', () {
    expect(describePageTitle(Uri.parse('/')), 'narlun | opening');
    expect(describePageTitle(Uri.parse('/home')), 'narlun | home');
    expect(describePageTitle(Uri.parse('/nearby')), 'narlun | nearby');
    expect(describePageTitle(Uri.parse('/rooms')), 'narlun | rooms');
    expect(
      describePageTitle(Uri.parse('/rooms?open_room=42')),
      'narlun | room',
    );
    expect(describePageTitle(Uri.parse('/profile')), 'narlun | profile');
    expect(describePageTitle(Uri.parse('/settings')), 'narlun | settings');
    expect(describePageTitle(Uri.parse('/signin')), 'narlun | sign in');
    expect(describePageTitle(Uri.parse('/signup')), 'narlun | sign up');
    expect(describePageTitle(Uri.parse('/invite')), 'narlun | invite');
    expect(
      describePageTitle(Uri.parse('/invite/token-123')),
      'narlun | invite',
    );
  });
}
