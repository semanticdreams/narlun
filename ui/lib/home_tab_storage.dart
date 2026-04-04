import 'home_tab_storage_default.dart'
    if (dart.library.html) 'home_tab_storage_browser.dart'
    as storage;

int? readStoredHomeTabIndex() => storage.readStoredHomeTabIndex();

void writeStoredHomeTabIndex(int index) => storage.writeStoredHomeTabIndex(index);

void clearStoredHomeTabIndexForTests() => storage.clearStoredHomeTabIndexForTests();
