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
      'Bob, Charlie, and 1 other are typing...',
    );

    expect(
      describeTypingParticipants([
        const RoomParticipant(id: 5, username: 'Eli'),
        const RoomParticipant(id: 4, username: 'Dana'),
        const RoomParticipant(id: 2, username: 'Bob'),
        const RoomParticipant(id: 3, username: 'Charlie'),
      ]),
      'Bob, Charlie, and 2 others are typing...',
    );
  });
}
