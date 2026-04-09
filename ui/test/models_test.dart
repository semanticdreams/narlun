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

  test('whatsapp group previews use the specialized label', () {
    final preview = MessagePreview.fromJson({
      'kind': 'whatsapp_group',
      'body': '',
      'whatsapp_group': {
        'invite_url': 'https://chat.whatsapp.com/InviteToken123',
      },
    });
    final message = ChatMessage.fromJson({
      'id': 'm-1',
      'kind': 'whatsapp_group',
      'body': '',
      'sender_id': 1,
      'timestamp': '2026-04-04T10:00:00.000Z',
      'whatsapp_group': {
        'invite_url': 'https://chat.whatsapp.com/InviteToken123',
      },
    });

    expect(preview.previewText, 'Join WhatsApp group');
    expect(message.displayText, 'Join WhatsApp group');
    expect(
      message.pendingMatchKey,
      'whatsapp:https://chat.whatsapp.com/InviteToken123',
    );
  });

  test('location previews use the specialized label', () {
    final preview = MessagePreview.fromJson({
      'kind': 'location',
      'body': '',
      'location': {'lat': 47.4979, 'lon': 19.0402, 'accuracy_meters': 12.4},
    });
    final message = ChatMessage.fromJson({
      'id': 'm-2',
      'kind': 'location',
      'body': '',
      'sender_id': 1,
      'timestamp': '2026-04-04T10:00:00.000Z',
      'location': {'lat': 47.4979, 'lon': 19.0402, 'accuracy_meters': 12.4},
    });

    expect(preview.previewText, 'Shared location');
    expect(message.displayText, 'Shared location');
    expect(message.location?.coordinateLabel, '47.49790, 19.04020');
    expect(message.location?.googleMapsUrl, contains('maps/search/'));
    expect(message.pendingMatchKey, 'location:47.497900:19.040200:12.4');
  });

  test('other room previews use the specialized label', () {
    final preview = MessagePreview.fromJson({
      'kind': 'other_room',
      'body': '',
      'other_room': {
        'room_id': 7,
        'invite_token': 'token-123',
        'expires_at': '2026-04-05T10:00:00.000Z',
        'name': 'Board games',
        'member_count': 3,
        'room_active': true,
      },
    });
    final message = ChatMessage.fromJson({
      'id': 'm-4',
      'kind': 'other_room',
      'body': '',
      'sender_id': 1,
      'timestamp': '2026-04-04T10:00:00.000Z',
      'other_room': {
        'room_id': 7,
        'invite_token': 'token-123',
        'expires_at': '2026-04-05T10:00:00.000Z',
        'name': 'Board games',
        'member_count': 3,
        'room_active': true,
      },
    });

    expect(preview.previewText, 'Other room');
    expect(message.displayText, 'Other room');
    expect(message.otherRoom?.title, 'Board games');
    expect(message.pendingMatchKey, 'other-room:7');
  });

  test('malformed location payloads are ignored instead of becoming 0,0', () {
    final preview = MessagePreview.fromJson({
      'kind': 'location',
      'body': '',
      'location': {'lon': 19.0402},
    });
    final message = ChatMessage.fromJson({
      'id': 'm-3',
      'kind': 'location',
      'body': '',
      'sender_id': 1,
      'timestamp': '2026-04-04T10:00:00.000Z',
      'location': {'lat': 'bad', 'lon': 19.0402},
    });

    expect(preview.location, isNull);
    expect(message.location, isNull);
    expect(message.displayText, 'Shared location');
  });
}
