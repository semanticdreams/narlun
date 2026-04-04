import 'dart:html' as html;

const _storedHomeTabIndexKey = 'narlun.homeTabIndex';

int? readStoredHomeTabIndex() {
  final value = html.window.localStorage[_storedHomeTabIndexKey];
  if (value == null || value.isEmpty) {
    return null;
  }
  return int.tryParse(value);
}

void writeStoredHomeTabIndex(int index) {
  html.window.localStorage[_storedHomeTabIndexKey] = '$index';
}

void clearStoredHomeTabIndexForTests() {
  html.window.localStorage.remove(_storedHomeTabIndexKey);
}
