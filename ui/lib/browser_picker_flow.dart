import 'dart:async';

Future<T?> awaitBrowserPickerResult<T>({
  required Stream<void> changeEvents,
  required Stream<void> focusEvents,
  required Future<T?> Function() readSelection,
  Duration cancelDelay = const Duration(milliseconds: 200),
  Duration timeout = const Duration(seconds: 30),
}) {
  final completer = Completer<T?>();
  late final StreamSubscription<void> changeSubscription;
  late final StreamSubscription<void> focusSubscription;
  Timer? cancelTimer;
  var changeSeen = false;

  Future<void> complete(T? value) async {
    cancelTimer?.cancel();
    await changeSubscription.cancel();
    await focusSubscription.cancel();
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  Future<void> completeError(Object error, StackTrace stackTrace) async {
    cancelTimer?.cancel();
    await changeSubscription.cancel();
    await focusSubscription.cancel();
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  changeSubscription = changeEvents.listen((_) async {
    changeSeen = true;
    try {
      await complete(await readSelection());
    } catch (error, stackTrace) {
      await completeError(error, stackTrace);
    }
  });

  focusSubscription = focusEvents.listen((_) {
    cancelTimer?.cancel();
    cancelTimer = Timer(cancelDelay, () {
      if (!changeSeen) {
        unawaited(complete(null));
      }
    });
  });

  return completer.future.timeout(
    timeout,
    onTimeout: () {
      unawaited(complete(null));
      return null;
    },
  );
}
