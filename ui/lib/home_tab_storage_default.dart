int? _storedHomeTabIndex;

int? readStoredHomeTabIndex() => _storedHomeTabIndex;

void writeStoredHomeTabIndex(int index) {
  _storedHomeTabIndex = index;
}

void clearStoredHomeTabIndexForTests() {
  _storedHomeTabIndex = null;
}
