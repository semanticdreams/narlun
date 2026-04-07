String describeLeaveRoomDialogBody({required bool showNearbyHint}) {
  if (showNearbyHint) {
    return 'You will leave this room. If another member is nearby, it may show up in Nearby again and you can request to rejoin.';
  }
  return 'You will leave this room.';
}
