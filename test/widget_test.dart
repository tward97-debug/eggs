import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/main.dart';

void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await const GameDataLoader().load();
  });

  testWidgets('loads the farm and opens generic common research',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(EggEmpireApp(gameData: data));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Egg Empire'), findsOneWidget);
    expect(find.text('Egg tier 1'), findsOneWidget);
    expect(find.textContaining('Farm cash'), findsOneWidget);
    expect(find.textContaining('Tap to hatch'), findsOneWidget);
    expect(find.text('Drone incoming'), findsNothing);
    expect(find.textContaining('Next drone in'), findsNothing);

    final firstHabitat = find.text('Habitat 1');
    await tester.drag(find.byType(ListView).first, const Offset(0, -550));
    await tester.pumpAndSettle();
    await tester.tap(firstHabitat);
    await tester.pumpAndSettle();
    expect(find.textContaining('Upgrade to Tier'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Research'));
    await tester.pump();

    expect(find.text('Common research'), findsOneWidget);
    expect(find.text('Research group 1'), findsOneWidget);
    expect(find.text('Upgrade 1'), findsOneWidget);
    expect(find.text('Egg tier 1'), findsOneWidget);
    expect(find.text('Comfortable Nests'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cash-balance-header')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('cash-balance-header'))).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(ListView).first).top + 1),
    );
  });

  testWidgets('settings expose display, offline, Piggy Bank, and reset options',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(EggEmpireApp(gameData: data));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(find.text('Piggy Bank'), findsOneWidget);
    expect(find.text('Crack Piggy Bank'), findsOneWidget);
    expect(find.text('Scientific number format'), findsOneWidget);
    expect(find.text('Offline summary'), findsOneWidget);
    expect(find.text('Reset all data'), findsOneWidget);
  });

  testWidgets('transport page shows individual fleet slots and upgrade choices',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(EggEmpireApp(gameData: data));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.text('Transport'));
    await tester.pump();

    expect(find.text('Vehicle 1'), findsOneWidget);
    expect(find.text('Vehicle 2'), findsOneWidget);
    expect(find.text('Trike'), findsOneWidget);
    expect(find.text('Empty · tap to buy'), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cash-balance-header')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('cash-balance-header'))).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(ListView).first).top + 1),
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vehicle 1'));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade to Transit Van'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
