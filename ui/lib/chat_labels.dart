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
  final remainingCount = activeParticipants.length - 2;
  final otherLabel = remainingCount == 1 ? 'other' : 'others';
  return '${activeParticipants[0].username}, ${activeParticipants[1].username}, and $remainingCount $otherLabel are typing...';
}
