import 'package:get_it/get_it.dart';
import 'dialog_service.dart';
import 'websocket.dart';

final locator = GetIt.instance;

void setupLocator() {
  locator.registerLazySingleton(() => DialogService());
  locator.registerLazySingleton(() => WebsocketService());
}
