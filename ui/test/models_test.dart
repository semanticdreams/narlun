import 'package:flutter_test/flutter_test.dart';

import 'package:narlun/models.dart';

void main() {
  test('unnamed group rooms fall back to participant names', () {
    const me = SessionUser(authenticated: true, id: 1, username: 'me');
    final room = RoomSummary(
      id: 7,
      isGroup: true,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'alice'),
        RoomParticipant(id: 3, username: 'bob'),
      ],
    );

    expect(room.displayTitleFor(me), 'alice, bob');
  });

  test('room summary parses push muted state', () {
    final room = RoomSummary.fromJson({
      'id': 7,
      'is_group': false,
      'updated_at': '2026-04-04T10:00:00.000Z',
      'participants': const [],
      'push_muted': true,
    });

    expect(room.pushMuted, isTrue);
  });
}
