import 'models.dart';

class RoomMessagesCache {
  final Map<int, List<ChatMessage>> _messagesByRoom =
      <int, List<ChatMessage>>{};
  final Set<int> _loadedRoomIds = <int>{};
  int? _sessionUserId;

  void syncSession(SessionUser? user) {
    final nextUserId = user?.authenticated == true && user?.id != null
        ? user!.id
        : null;
    if (_sessionUserId == nextUserId) {
      return;
    }
    _sessionUserId = nextUserId;
    _messagesByRoom.clear();
    _loadedRoomIds.clear();
  }

  bool hasLoadedRoom(int roomId) => _loadedRoomIds.contains(roomId);

  List<ChatMessage>? cachedMessagesFor(int roomId) {
    final messages = _messagesByRoom[roomId];
    if (messages == null) {
      return null;
    }
    return List<ChatMessage>.from(messages);
  }

  void storeMessages(int roomId, List<ChatMessage> messages) {
    _messagesByRoom[roomId] = List<ChatMessage>.from(messages);
    _loadedRoomIds.add(roomId);
  }

  void clearRoom(int roomId) {
    _messagesByRoom.remove(roomId);
    _loadedRoomIds.remove(roomId);
  }
}
