import 'models.dart';

String? describeTypingParticipants(Iterable<RoomParticipant> participants) {
  final activeParticipants = participants.toList()
    ..sort((left, right) => left.username.compareTo(right.username));
  if (activeParticipants.isEmpty) {
    return null;
  }
  if (activeParticipants.length == 1) {
    return '${activeParticipants.first.username} is typing...';
  }
  if (activeParticipants.length == 2) {
    return '${activeParticipants[0].username} and ${activeParticipants[1].username} are typing...';
  }
  return '${activeParticipants[0].username}, ${activeParticipants[1].username}, and ${activeParticipants.length - 2} others are typing...';
}
