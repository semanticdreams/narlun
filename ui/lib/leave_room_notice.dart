String describeLeaveRoomDialogBody({
  required bool isDirectRoom,
  required bool showNearbyHint,
}) {
  if (isDirectRoom) {
    return 'You will leave this conversation. You can start a new one later.';
  }
  if (showNearbyHint) {
    return 'You will leave this room. If another member is nearby, it may show up in Nearby again and you can request to rejoin.';
  }
  return 'You will leave this room.';
}
