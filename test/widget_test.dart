import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    expect(find.textContaining('Slot '), findsNWidgets(4));
    expect(find.text('Slot 1 · Coop'), findsOneWidget);
    expect(find.textContaining('chickens capacity'), findsWidgets);
    expect(
      find.byKey(const ValueKey('buy-habitat-slot-1-tier-0')),
      findsNothing,
    );
    await tester.tap(find.text('Slot 2 · Empty'));
    await tester.pumpAndSettle();
    // Every habitat tier is offered on an empty slot.
    expect(
      find.byKey(const ValueKey('buy-habitat-slot-1-tier-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('buy-habitat-slot-1-tier-1')),
      findsOneWidget,
    );
    await tester.tap(find.text('Slot 1 · Coop'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('upgrade-habitat-slot-0-tier-1')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close Habitats'));
    await tester.pumpAndSettle();

    final transportButton = find.byKey(const ValueKey('open-transport'));
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
    expect(find.textContaining('Slot '), findsNWidgets(4));
    expect(find.text('Slot 1 · Trike'), findsOneWidget);
    expect(find.textContaining('eggs/min capacity'), findsWidgets);
    await tester.tap(find.text('Slot 2 · Empty'));
    await tester.pumpAndSettle();
    // The free trike is already owned, so the first option is the van.
    expect(
      find.byKey(const ValueKey('buy-vehicle-slot-1-tier-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('buy-vehicle-slot-1-tier-1')),
      findsOneWidget,
    );
  });

  testWidgets('farm screen fits a narrow phone without overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpGame(tester);

    expect(find.byKey(const ValueKey('farm-cash-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('hatch-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding the hatch button moves chickens onto the farm',
      (tester) async {
    await pumpGame(tester);
    expect(find.textContaining('Chickens 0 / 250'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hatch-button')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Chickens 0 / 250'), findsNothing);
  });

  testWidgets('silo menu opens and pages return to the farm', (tester) async {
    await pumpGame(tester);
    await tester.tap(find.byKey(const ValueKey('open-silos')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 silos'), findsOneWidget);
    expect(find.byKey(const ValueKey('buy-silo')), findsOneWidget);
    await tester.tap(find.byTooltip('Close Silos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Boosts'));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('hatch-button')).hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('Back to farm'));
    await tester.pump();
    expect(find.byKey(const ValueKey('hatch-button')).hitTestable(),
        findsOneWidget);
  });

  testWidgets('drone appears, claims its reward, and disappears',
      (tester) async {
    await pumpGame(tester, simulateDroneClockForTesting: true);
    // A red dot marks the spot for a second before the drone shows.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('drone-warning')), findsOneWidget);
    expect(find.byKey(const ValueKey('drone-button')), findsNothing);
    await waitForDrone(tester);
    expect(find.byKey(const ValueKey('drone-warning')), findsNothing);

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
    // Locked tiers start collapsed; unlocked ones start open.
    expect(lockedRow, findsNothing);
    await tester.scrollUntilVisible(
      find.text('Tier 2'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Tier 2'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      lockedRow,
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.textContaining('Unlocks after 30 total research levels'),
      findsWidgets,
    );

    await tester.ensureVisible(find.text('Tier 2'));
    await tester.tap(find.text('Tier 2'));
    await tester.pumpAndSettle();
    expect(lockedRow, findsNothing);
  });

  testWidgets('garden opens from More and plants a crop', (tester) async {
    // A small phone, so an overflowing plot grid fails the test.
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpGame(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garden'));
    await tester.pumpAndSettle();

    expect(find.text('Tap to plant'), findsNWidgets(8));
    await tester.tap(find.byKey(const ValueKey('garden-plot-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 / 32 Corn harvested'), findsOneWidget);
    expect(find.byKey(const ValueKey('plant-candy_corn')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plant-corn')));
    await tester.pumpAndSettle();
    expect(find.text('Tap to plant'), findsNWidgets(7));
    expect(find.text('Corn'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garden-goals')));
    await tester.pumpAndSettle();
    expect(find.text('Harvest 32 Corn'), findsOneWidget);
    expect(find.textContaining('0 / 32 · unlocks Crazy Corn'), findsOneWidget);
    expect(find.text('Harvest 40 Super Crazy Corn'), findsOneWidget);
  });

  testWidgets('haptic feedback setting is only shown in Settings',
      (tester) async {
    await pumpGame(tester);
    expect(find.text('Haptic feedback'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(find.text('Vibrate when chickens hatch.'), findsOneWidget);
    final hapticsSwitch = find.byKey(const ValueKey('haptics-setting'));
    expect(tester.widget<SwitchListTile>(hapticsSwitch).value, isTrue);
    await tester.tap(hapticsSwitch);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(hapticsSwitch).value, isFalse);
  });
}
