import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:narlun/app_update_banner.dart';
import 'package:narlun/app_update_service.dart';

class FakeAppUpdateService extends AppUpdateService {
  FakeAppUpdateService({
    this.supported = true,
    this.updateAvailable = false,
    this.applyingUpdate = false,
  });

  final bool supported;
  bool updateAvailable;
  bool applyingUpdate;
  int checkCalls = 0;
  int applyCalls = 0;

  @override
  bool get isSupported => supported;

  @override
  bool get isUpdateAvailable => updateAvailable;

  @override
  bool get isApplyingUpdate => applyingUpdate;

  @override
  Future<void> applyUpdate() async {
    applyCalls += 1;
  }

  @override
  Future<void> checkForUpdate() async {
    checkCalls += 1;
  }
}

void main() {
  testWidgets('stays hidden when no update is available', (tester) async {
    final updateService = FakeAppUpdateService(updateAvailable: false);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppUpdateService>.value(
        value: updateService,
        child: const MaterialApp(
          home: AppUpdateBanner(
            child: Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(
      find.text('A newer version of Narlun is ready. Reload to update.'),
      findsNothing,
    );
    expect(find.text('Reload'), findsNothing);
  });

  testWidgets('shows the update banner and reloads on tap', (tester) async {
    final updateService = FakeAppUpdateService(updateAvailable: true);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppUpdateService>.value(
        value: updateService,
        child: const MaterialApp(
          home: AppUpdateBanner(
            child: Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );

    expect(
      find.text('A newer version of Narlun is ready. Reload to update.'),
      findsOneWidget,
    );
    expect(find.text('Reload'), findsOneWidget);

    await tester.tap(find.text('Reload'));
    await tester.pump();

    expect(updateService.applyCalls, 1);
  });

  testWidgets('shows reloading state while an update is being applied', (
    tester,
  ) async {
    final updateService = FakeAppUpdateService(
      updateAvailable: true,
      applyingUpdate: true,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppUpdateService>.value(
        value: updateService,
        child: const MaterialApp(
          home: AppUpdateBanner(
            child: Scaffold(body: Text('Home')),
          ),
        ),
      ),
    );

    expect(find.text('Reloading...'), findsOneWidget);
    expect(find.text('Reload'), findsNothing);
  });
}
