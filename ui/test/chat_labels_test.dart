import 'package:flutter_test/flutter_test.dart';

import 'package:narlun/chat_labels.dart';
import 'package:narlun/models.dart';

void main() {
  test('describeTypingParticipants handles one two and many users', () {
    expect(
      describeTypingParticipants([
        const RoomParticipant(id: 2, username: 'Bob'),
      ]),
      'Bob is typing...',
    );

    expect(
      describeTypingParticipants([
        const RoomParticipant(id: 3, username: 'Charlie'),
        const RoomParticipant(id: 2, username: 'Bob'),
      ]),
      'Bob and Charlie are typing...',
    );

    expect(
      describeTypingParticipants([
        const RoomParticipant(id: 4, username: 'Dana'),
        const RoomParticipant(id: 2, username: 'Bob'),
        const RoomParticipant(id: 3, username: 'Charlie'),
      ]),
      'Bob, Charlie, and 1 others are typing...',
    );
  });

  test('describeSeenByParticipants handles direct and group receipts', () {
    expect(
      describeSeenByParticipants(
        const [RoomParticipant(id: 2, username: 'Bob')],
        isDirectRoom: true,
      ),
      'Seen',
    );

    expect(
      describeSeenByParticipants(
        const [
          RoomParticipant(id: 2, username: 'Bob'),
          RoomParticipant(id: 3, username: 'Charlie'),
        ],
        isDirectRoom: false,
      ),
      'Seen by Bob and Charlie',
    );

    expect(
      describeSeenByParticipants(
        const [
          RoomParticipant(id: 4, username: 'Dana'),
          RoomParticipant(id: 2, username: 'Bob'),
          RoomParticipant(id: 3, username: 'Charlie'),
        ],
        isDirectRoom: false,
      ),
      'Seen by Bob, Charlie, and 1 others',
    );
  });
}
