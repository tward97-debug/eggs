import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:egg_empire/config/balance.dart';
import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/ui/game_screen.dart';

void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await const GameDataLoader().load();
  });

  Future<void> pumpGame(
    WidgetTester tester, {
    bool simulateDroneClockForTesting = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          data: data,
          simulateDroneClockForTesting: simulateDroneClockForTesting,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> waitForDrone(WidgetTester tester) async {
    for (var attempt = 0;
        attempt < 210 &&
            find.byKey(const ValueKey('drone-button')).evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('drone-button')), findsOneWidget);
  }

  testWidgets('Farm opens separate habitat and transport menus',
      (tester) async {
    await pumpGame(tester);

    final habitatsButton = find.byKey(const ValueKey('open-habitats'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(habitatsButton);
    await tester.tap(habitatsButton);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('management-menu-title')),
          )
          .data,
      'Habitats',
    );
    expect(
        find.byKey(const ValueKey('management-cash-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('buy-habitat-tier-0')), findsOneWidget);
    expect(find.textContaining('chickens capacity'), findsWidgets);
    await tester.tap(find.byTooltip('Close Habitats'));
    await tester.pumpAndSettle();

    final transportButton = find.byKey(const ValueKey('open-transport'));
    await tester.ensureVisible(transportButton);
    await tester.tap(transportButton);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('management-menu-title')),
          )
          .data,
      'Transport',
    );
    expect(find.byKey(const ValueKey('buy-vehicle-tier-0')), findsOneWidget);
    expect(find.textContaining('eggs/min capacity'), findsWidgets);
  });

  testWidgets('cash panel reserves room for the Drone button on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpGame(tester);

    final reservedText = tester.widget<Padding>(
      find.byKey(const ValueKey('cash-panel-text-reserved-space')),
    );
    expect(
      (reservedText.padding as EdgeInsets).right,
      greaterThanOrEqualTo(BalanceConfig.droneButtonDiameter + 8),
    );
    expect(find.byKey(const ValueKey('farm-cash-panel')), findsOneWidget);
  });

  testWidgets('drone appears, claims its reward, and disappears',
      (tester) async {
    await pumpGame(tester, simulateDroneClockForTesting: true);
    await waitForDrone(tester);

    await tester.tap(find.byKey(const ValueKey('drone-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('drone-button')), findsNothing);
    expect(find.byType(Icon), findsWidgets);
  });

  testWidgets('unclaimed drone disappears when its visible duration ends',
      (tester) async {
    await pumpGame(tester, simulateDroneClockForTesting: true);
    await waitForDrone(tester);

    for (var tick = 0; tick < 7; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('drone-button')), findsNothing);
  });

  testWidgets('research cards show level, readable effects, costs, and locks',
      (tester) async {
    await pumpGame(tester);
    await tester.tap(find.text('Research'));
    await tester.pump();

    final common = data.commonResearch.first;
    final firstRow = find.byKey(ValueKey('research-item-${common.id}'));
    expect(firstRow, findsOneWidget);
    expect(find.text('0 / ${common.maxLevel}'), findsOneWidget);
    expect(find.textContaining('Per level:'), findsWidgets);
    expect(find.textContaining('Now:'), findsWidgets);
    expect(find.textContaining('Next cost:'), findsWidgets);

    final lockedResearch =
        data.commonResearch.firstWhere((item) => item.tier == 2);
    final lockedRow = find.byKey(
      ValueKey('research-item-${lockedResearch.id}'),
    );
    await tester.scrollUntilVisible(
      lockedRow,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Unlocks after 10 total research levels'),
      findsWidgets,
    );
  });

  testWidgets('haptic feedback setting is only shown in Settings',
      (tester) async {
    await pumpGame(tester);
    expect(find.text('Haptic feedback'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(find.text('Vibrate when chickens hatch.'), findsOneWidget);
    final hapticsSwitch = find.byKey(const ValueKey('haptics-setting'));
    expect(tester.widget<SwitchListTile>(hapticsSwitch).value, isTrue);
    await tester.tap(hapticsSwitch);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(hapticsSwitch).value, isFalse);
  });
}
