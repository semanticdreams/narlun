import 'leave_room_notice_storage_default.dart'
    if (dart.library.html) 'leave_room_notice_storage_browser.dart'
    as storage;

bool hasSeenLeaveRoomInfo(int userId) => storage.hasSeenLeaveRoomInfo(userId);

void markLeaveRoomInfoSeen(int userId) => storage.markLeaveRoomInfoSeen(userId);

void clearLeaveRoomInfoStorageForTests() =>
    storage.clearLeaveRoomInfoStorageForTests();
