import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:egg_empire/config/balance.dart';
import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/game/engine.dart';
import 'package:egg_empire/save/game_save.dart';
import 'package:egg_empire/ui/game_session.dart';

void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await const GameDataLoader().load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('press-and-hold hatching', () {
    test('a quick tap hatches six chickens and then releases', () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );

      expect(session.startHatching(), 6);
      session.stopHatching();
      expect(session.isHoldingHatch, isFalse);
      expect(session.engine.state.chickens, 6);

      session.dispose();
    });

    test('rapid taps each release a separate six-chicken batch', () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );

      for (var tap = 0; tap < 8; tap++) {
        expect(session.startHatching(), 6);
        session.stopHatching();
      }

      expect(session.engine.state.chickens, 48);
      expect(session.engine.state.hatcheryStock, 202);
      expect(session.isHoldingHatch, isFalse);
      session.dispose();
    });

    test('drains stock at the configured hold rate', () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );

      expect(session.startHatching(), 6);
      expect(session.advance(1), 10);
      expect(session.engine.state.hatcheryStock, 234);
      expect(session.engine.state.chickens, 16);

      session.dispose();
    });

    test('adds two chickens per second for each Hold to Hatch level', () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );
      session.engine.state.epicResearchLevels['hold_to_hatch'] = 1;

      expect(session.engine.holdHatchPerSecond, 12);

      session.dispose();
    });

    test('releases a held hatch when the session is paused', () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );
      session.startHatching();

      await session.pause();

      expect(session.isHoldingHatch, isFalse);
      session.dispose();
    });

    test('stops at empty stock without hatching unavailable chickens',
        () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );
      session.engine.state.hatcheryStock = 7;

      expect(session.startHatching(), 6);
      expect(session.advance(1), 1);
      expect(session.isHoldingHatch, isFalse);
      expect(session.engine.state.hatcheryStock, 0);
      expect(session.engine.state.chickens, 7);

      session.dispose();
    });

    test('stops at full habitats without spending hatchery stock', () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );
      session.engine.state.chickens = session.engine.totalHabCapacity - 1;
      final stockBefore = session.engine.state.hatcheryStock;

      expect(session.startHatching(), 1);
      expect(session.isHoldingHatch, isFalse);
      expect(session.advance(1), 0);
      expect(session.engine.state.hatcheryStock, stockBefore);
      expect(
        session.engine.state.chickens,
        session.engine.totalHabCapacity,
      );

      session.dispose();
    });

    test('retains fractional chicken progress between updates', () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );

      session.startHatching();
      expect(session.advance(0.05), 0);
      expect(session.engine.state.hatcheryStock, 244);
      expect(session.advance(0.05), 1);
      expect(session.engine.state.hatcheryStock, 243);
      expect(session.engine.state.chickens, 7);

      session.dispose();
    });

    test('refills stock at configured rate while hatching is released',
        () async {
      final session = await GameSession.restore(
        data,
        now: DateTime.utc(2025),
      );
      session.engine.state.hatcheryStock = 0;

      expect(session.startHatching(), 0);
      session.advance(1);

      expect(session.engine.state.hatcheryStock, closeTo(6, 1e-9));
      expect(
        session.engine.hatcheryRefillPerMinute,
        BalanceConfig.hatcheryRefillPerMin,
      );

      session.dispose();
    });
  });

  test('saves and loads the complete game state with a UTC timestamp',
      () async {
    final repository = const GameSaveRepository();
    final engine = GameEngine(data: data);
    engine.state.cash = 1234.5;
    engine.state.chickens = 42;
    engine.state.hatcheryStock = 17;
    engine.state.piggyBankGoldenEggs = 91;
    engine.state.runningChickenBatches.add(
      const RunningChickenBatch(chickens: 12, secondsRemaining: 8),
    );
    engine.state.commonResearchLevels['comfy_nests'] = 3;
    engine.state.epicResearchLevels['hold_to_hatch'] = 2;
    engine.state.hapticsEnabled = false;
    final savedAt = DateTime.parse('2025-01-02T03:04:05-05:00');

    await repository.save(engine.state, savedAt);
    final loaded = await repository.load(data);

    expect(loaded, isNotNull);
    expect(loaded!.lastSavedAt, savedAt.toUtc());
    expect(loaded.state.toJson(), engine.state.toJson());
  });

  test('reset all data clears permanent progress and writes a fresh save',
      () async {
    final session = await GameSession.restore(
      data,
      now: DateTime.utc(2025),
    );
    session.engine.state.cash = 123;
    session.engine.state.goldenEggs = 456;
    session.engine.state.soulEggs = 789;
    session.engine.state.piggyBankGoldenEggs = 12;

    await session.resetAllData(now: DateTime.utc(2025, 1, 2));
    final saved = await const GameSaveRepository().load(data);

    expect(session.engine.state.cash, 0);
    expect(session.engine.state.goldenEggs, 0);
    expect(session.engine.state.soulEggs, 0);
    expect(session.engine.state.piggyBankGoldenEggs, 0);
    expect(saved!.state.toJson(), session.engine.state.toJson());
    expect(saved.lastSavedAt, DateTime.utc(2025, 1, 2));
    await session.close();
  });

  test('migrates duplicate habitat slots from older saves', () async {
    final preferences = await SharedPreferences.getInstance();
    final engine = GameEngine(data: data);
    final legacyState = engine.state.toJson();
    legacyState['habs'] = [
      {'tierIndex': 0, 'slotIndex': 0},
      {'tierIndex': 1, 'slotIndex': 0},
      {'tierIndex': 2, 'slotIndex': 0},
    ];
    await preferences.setString(
      BalanceConfig.savePreferenceKey,
      jsonEncode({
        'version': BalanceConfig.saveFormatVersion,
        'lastSavedAt': DateTime.utc(2025).toIso8601String(),
        'state': legacyState,
      }),
    );

    final loaded = await const GameSaveRepository().load(data);

    expect(loaded, isNotNull);
    expect(
      loaded!.state.habs.map((hab) => hab.tierIndex),
      [0, 1, 2],
    );
    expect(
      loaded.state.habs.map((hab) => hab.slotIndex).toSet(),
      {0, 1, 2},
    );
  });

  test('assigns stable slots to vehicles in legacy saves', () async {
    final preferences = await SharedPreferences.getInstance();
    final engine = GameEngine(data: data);
    final legacyState = engine.state.toJson();
    legacyState['vehicles'] = [
      {'tierIndex': 0, 'unitNumber': 1},
      {'tierIndex': 1, 'unitNumber': 1},
    ];
    await preferences.setString(
      BalanceConfig.savePreferenceKey,
      jsonEncode({
        'version': BalanceConfig.saveFormatVersion,
        'lastSavedAt': DateTime.utc(2025).toIso8601String(),
        'state': legacyState,
      }),
    );

    final loaded = await const GameSaveRepository().load(data);

    expect(loaded!.state.vehicles.map((vehicle) => vehicle.slotIndex), [0, 1]);
  });

  test('treats a save timestamp in the future as zero away time', () async {
    final repository = const GameSaveRepository();
    final engine = GameEngine(data: data);
    engine.state.cash = 123;
    final futureSavedAt = DateTime.utc(2025, 1, 2);
    await repository.save(engine.state, futureSavedAt);

    final session = await GameSession.restore(
      data,
      now: DateTime.utc(2025, 1, 1),
    );

    expect(session.offlineProgress?.elapsedSeconds, 0);
    expect(session.engine.state.cash, 123);
    await session.close();
  });

  test('offline simulation matches 600 one-second game updates', () {
    final offlineEngine = GameEngine(data: data);
    final onlineEngine = GameEngine(data: data);
    for (final engine in [offlineEngine, onlineEngine]) {
      engine.state.chickens = 100;
      engine.state.hatcheryStock = 100;
      engine.state.commonResearchLevels['internal_hatcheries'] = 10;
    }

    final offline = offlineEngine.simulateOffline(600);
    for (var second = 0; second < 600; second++) {
      onlineEngine.tick(1);
    }

    expect(offline.elapsedSeconds, 600);
    expect(offlineEngine.state.chickens,
        closeTo(onlineEngine.state.chickens, 0.001));
    expect(offlineEngine.state.hatcheryStock,
        closeTo(onlineEngine.state.hatcheryStock, 0.001));
    expect(offlineEngine.state.cash, closeTo(onlineEngine.state.cash, 0.1));
    expect(
      offlineEngine.state.cashEarnedThisRun,
      closeTo(onlineEngine.state.cashEarnedThisRun, 0.1),
    );
  });

  test('resume catches up offline internal hatchery growth', () async {
    final startedAt = DateTime.utc(2025, 1, 1);
    final session = await GameSession.restore(data, now: startedAt);
    session.engine.state.commonResearchLevels['internal_hatcheries'] = 10;
    session.engine.state.epicResearchLevels['internal_hatchery_calm'] = 2;

    await session.pause(savedAt: startedAt);
    expect(session.isAutosaving, isFalse);

    final progress = await session.resume(
      now: startedAt.add(const Duration(minutes: 1)),
    );

    final expectedAwayGrowth = session.engine.flatResearchBonus('ihrPerHab') *
        session.engine.habCount *
        session.engine.epicResearchMultiplier('ihrMult') *
        session.engine.epicResearchMultiplier('ihrAwayMult');
    expect(progress.elapsedSeconds, 60);
    expect(progress.chickensAdded, closeTo(expectedAwayGrowth, 1e-6));
    expect(session.engine.state.chickens, closeTo(expectedAwayGrowth, 1e-6));
    expect(session.isAutosaving, isTrue);
    await session.close();
  });

  test('repeated background lifecycle events preserve offline time', () async {
    final startedAt = DateTime.utc(2025, 1, 1);
    final firstPauseAt = startedAt.add(const Duration(minutes: 1));
    final session = await GameSession.restore(data, now: startedAt);

    await session.pause(savedAt: firstPauseAt);
    await session.pause(savedAt: startedAt.add(const Duration(minutes: 2)));
    expect(session.lastSavedAt, firstPauseAt);

    final progress = await session.resume(
      now: startedAt.add(const Duration(minutes: 3)),
    );

    expect(progress.elapsedSeconds, 120);
    await session.pause(savedAt: startedAt.add(const Duration(minutes: 4)));
    await session.close();
    expect(session.lastSavedAt, startedAt.add(const Duration(minutes: 4)));
  });

  test('offline simulation respects silo cap and boost expiry after chunks',
      () {
    final oneLongCatchUp = GameEngine(data: data);
    final twoCatchUps = GameEngine(data: data);
    for (final engine in [oneLongCatchUp, twoCatchUps]) {
      engine.state.siloCount = 20;
      engine.state.chickens = 100;
      engine.state.activeBoostSeconds['best_bird_feed'] = 36100;
      engine.state.activeBoostMultipliers['best_bird_feed'] = 2;
    }

    final longProgress = oneLongCatchUp.simulateOffline(100000);
    twoCatchUps.simulateOffline(36000);
    twoCatchUps.simulateOffline(36000);

    expect(longProgress.elapsedSeconds, 20 * 60 * 60);
    expect(oneLongCatchUp.state.activeBoostSeconds, isEmpty);
    expect(oneLongCatchUp.state.chickens, twoCatchUps.state.chickens);
    expect(oneLongCatchUp.state.hatcheryStock, twoCatchUps.state.hatcheryStock);
    expect(oneLongCatchUp.state.cash, closeTo(twoCatchUps.state.cash, 0.1));
  });
}
