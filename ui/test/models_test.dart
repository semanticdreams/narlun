import 'package:flutter_test/flutter_test.dart';

import 'package:narlun/models.dart';

void main() {
  test('unnamed multi-member rooms fall back to participant names', () {
    const me = SessionUser(authenticated: true, id: 1, username: 'me');
    final room = RoomSummary(
      id: 7,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'alice'),
        RoomParticipant(id: 3, username: 'bob'),
      ],
    );

    expect(room.displayTitleFor(me), 'alice, bob');
  });

  test('unnamed two-person rooms use the other member name as the title', () {
    const me = SessionUser(authenticated: true, id: 1, username: 'me');
    final room = RoomSummary(
      id: 8,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'alice'),
      ],
    );

    expect(room.displayTitleFor(me), 'alice');
  });

  test('unnamed two-person rooms fall back to the other member picture', () {
    const me = SessionUser(authenticated: true, id: 1, username: 'me');
    final room = RoomSummary(
      id: 9,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(
          id: 2,
          username: 'alice',
          picture: 'https://example.com/alice.png',
        ),
      ],
    );

    expect(room.displayPictureFor(me), 'https://example.com/alice.png');
  });

  test('room summary parses push muted state', () {
    final room = RoomSummary.fromJson({
      'id': 7,
      'updated_at': '2026-04-04T10:00:00.000Z',
      'participants': const [],
      'push_muted': true,
    });

    expect(room.pushMuted, isTrue);
  });
}
