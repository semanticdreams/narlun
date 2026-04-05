final Set<int> _seenLeaveRoomInfoUserIds = <int>{};

bool hasSeenLeaveRoomInfo(int userId) {
  return _seenLeaveRoomInfoUserIds.contains(userId);
}

void markLeaveRoomInfoSeen(int userId) {
  _seenLeaveRoomInfoUserIds.add(userId);
}

void clearLeaveRoomInfoStorageForTests() {
  _seenLeaveRoomInfoUserIds.clear();
}
