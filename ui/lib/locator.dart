import 'package:get_it/get_it.dart';
import 'dialog_service.dart';
import 'websocket.dart';

final locator = GetIt.instance;

Future<void> setupLocator({
  bool reset = false,
  DialogService? dialogService,
  WebsocketService? websocketService,
}) async {
  if (reset) {
    if (locator.isRegistered<WebsocketService>()) {
      await locator<WebsocketService>().close();
    }
    await locator.reset();
  }

  if (!locator.isRegistered<DialogService>()) {
    locator.registerLazySingleton<DialogService>(
      () => dialogService ?? DialogService(),
    );
  }
  if (!locator.isRegistered<WebsocketService>()) {
    locator.registerLazySingleton<WebsocketService>(
      () => websocketService ?? WebsocketService(),
    );
  }
}
