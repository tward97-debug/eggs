import 'dart:convert';
import 'dart:math' as math;

import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/game/engine.dart';
import 'package:egg_empire/ui/garden_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _hour = 3600000;
const _minute = 60000;

void main() {
  late GameData data;
  late GameEngine engine;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await const GameDataLoader().load();
  });

  setUp(() {
    engine = GameEngine(data: data);
    engine.state.cash = 1e9;
  });

  test('a crop grows, is ready for 45 minutes, then withers', () {
    expect(engine.plotStatus(0, 0), PlotStatus.empty);
    expect(engine.plantCrop(0, 'corn', 1000), isTrue);

    expect(engine.plotStatus(0, 1000), PlotStatus.growing);
    expect(engine.plotStatus(0, 1000 + 6 * _hour - 1), PlotStatus.growing);
    expect(engine.plotStatus(0, 1000 + 6 * _hour), PlotStatus.ready);
    expect(
      engine.plotStatus(0, 1000 + 6 * _hour + 45 * _minute - 1),
      PlotStatus.ready,
    );
    expect(
      engine.plotStatus(0, 1000 + 6 * _hour + 45 * _minute),
      PlotStatus.withered,
    );
    // Days later it is still simply withered.
    expect(engine.plotStatus(0, 1000 + 240 * _hour), PlotStatus.withered);
  });

  test('withered crops give nothing and must be cleared to replant', () {
    engine.plantCrop(0, 'corn', 0);
    const late = 7 * _hour;

    expect(engine.harvestPlot(0, late), isFalse);
    expect(engine.plantCrop(0, 'corn', late), isFalse);
    expect(engine.clearPlot(0, late), isTrue);
    expect(engine.state.soulEggs, 0);
    expect(engine.cropHarvested('corn'), 0);
    expect(engine.plantCrop(0, 'corn', late), isTrue);
  });

  test('harvesting pays once, however often it is tapped', () {
    engine.plantCrop(0, 'corn', 0);

    expect(engine.harvestPlot(0, 5 * _hour), isFalse);
    expect(engine.harvestPlot(0, 6 * _hour), isTrue);
    expect(engine.harvestPlot(0, 6 * _hour), isFalse);
    expect(engine.state.soulEggs, engine.crop('corn').amount);
    expect(engine.cropHarvested('corn'), 1);
  });

  test('a seed costs 90 seconds of earnings, paid when planting', () {
    engine.state.chickens = 100;
    final cost = engine.seedCost;
    expect(cost, closeTo(engine.cashPerSecond * 90, 1e-9));
    expect(cost, greaterThan(0));

    engine.state.cash = cost - 0.01;
    expect(engine.plantCrop(0, 'corn', 0), isFalse);
    engine.state.cash = cost;
    expect(engine.plantCrop(0, 'corn', 0), isTrue);
    expect(engine.state.cash, closeTo(0, 1e-9));
    // An occupied plot cannot be planted twice.
    engine.state.cash = cost;
    expect(engine.plantCrop(0, 'corn', 0), isFalse);
    expect(engine.plantCrop(99, 'corn', 0), isFalse);
  });

  test('crops unlock from lifetime harvests of the crop before', () {
    final crazyCorn = engine.crop('crazy_corn');
    expect(engine.isCropUnlocked(engine.crop('corn')), isTrue);
    expect(engine.isCropUnlocked(engine.crop('soul_root')), isTrue);
    expect(engine.isCropUnlocked(crazyCorn), isFalse);
    expect(engine.plantCrop(0, 'crazy_corn', 0), isFalse);

    engine.state.garden.harvested['corn'] = crazyCorn.unlockHarvests - 1;
    expect(engine.isCropUnlocked(crazyCorn), isFalse);
    engine.state.garden.harvested['corn'] = crazyCorn.unlockHarvests;
    expect(engine.isCropUnlocked(crazyCorn), isTrue);
    expect(engine.plantCrop(0, 'crazy_corn', 0), isTrue);
  });

  test('unlocking a crop pays a one-time share of the Soul Eggs held', () {
    final crazyCorn = engine.crop('crazy_corn');
    engine.state.soulEggs = 1000;
    engine.state.garden.harvested['corn'] = crazyCorn.unlockHarvests - 2;

    void harvestCorn() {
      engine.plantCrop(0, 'corn', 0);
      expect(engine.harvestPlot(0, 6 * _hour), isTrue);
    }

    harvestCorn();
    expect(engine.state.garden.newUnlockRewards, isEmpty);

    final before = engine.state.soulEggs + engine.crop('corn').amount;
    final reward =
        (before * crazyCorn.unlockRewardSoulEggPercent / 100).floorToDouble();
    harvestCorn();
    expect(engine.state.soulEggs, closeTo(before + reward, 1e-9));
    expect(engine.state.garden.newUnlockRewards.single.cropName, 'Crazy Corn');
    expect(engine.state.garden.newUnlockRewards.single.soulEggs, reward);

    // Only once, and the saved game remembers it.
    harvestCorn();
    expect(engine.state.garden.newUnlockRewards, hasLength(1));
    final json =
        jsonDecode(jsonEncode(engine.state.toJson())) as Map<String, Object?>;
    expect(
      GameState.fromJson(json, data).garden.unlockRewardsPaid,
      {'crazy_corn'},
    );
  });

  test('a small Soul Egg balance gets the floor reward, even late', () {
    final crazyCorn = engine.crop('crazy_corn');
    // Already past the count, as for a save from before rewards existed.
    engine.state.garden.harvested['corn'] = crazyCorn.unlockHarvests + 5;

    engine.plantCrop(0, 'corn', 0);
    engine.harvestPlot(0, 6 * _hour);

    expect(
      engine.state.garden.newUnlockRewards.single.soulEggs,
      crazyCorn.unlockRewardSoulEggFloor,
    );
    expect(
      engine.state.soulEggs,
      closeTo(
        engine.crop('corn').amount + crazyCorn.unlockRewardSoulEggFloor,
        1e-9,
      ),
    );
  });

  test('a corn crop is retired once the next one is unlocked', () {
    final corn = engine.crop('corn');
    expect(engine.isCropRetired(corn), isFalse);
    engine.plantCrop(0, 'corn', 0);
    engine.state.garden.harvested['corn'] =
        engine.crop('crazy_corn').unlockHarvests;

    expect(engine.isCropRetired(corn), isTrue);
    expect(engine.isCropRetired(engine.crop('crazy_corn')), isFalse);
    expect(engine.isCropRetired(engine.crop('soul_root')), isFalse);

    // "Replant same" moves the plot on to the crop that replaced it.
    engine.harvestAll(6 * _hour);
    expect(engine.replantAll(6 * _hour), 1);
    expect(engine.state.garden.planted[0]!.cropId, 'crazy_corn');
  });

  test('extra plots cost 5 to 1000 Golden Eggs in a straight line', () {
    expect(engine.gardenPlotCount, 8);
    expect(engine.buyPlot(), isFalse);

    engine.state.goldenEggs = 1e6;
    final prices = <double>[];
    while (engine.nextPlotPrice.isFinite) {
      prices.add(engine.nextPlotPrice);
      expect(engine.buyPlot(), isTrue);
    }

    expect(prices, hasLength(16));
    expect(prices.first, 5);
    expect(prices.last, closeTo(1000, 1e-9));
    expect(prices[1] - prices[0], closeTo(prices[15] - prices[14], 1e-9));
    expect(engine.gardenPlotCount, 24);
    expect(engine.buyPlot(), isFalse);
    expect(
      engine.state.goldenEggs,
      closeTo(1e6 - prices.reduce((a, b) => a + b), 1e-6),
    );
  });

  test('a year of daily Candy Corn on 8 plots is worth 120 Prophecy Eggs', () {
    engine.state.soulEggs = 10;
    final before = engine.earningsMultiplier - 1;
    engine.state.garden.harvested['candy_corn'] = 8 * 365;

    final ratio = (engine.earningsMultiplier - 1) / before;
    expect(ratio / math.pow(1.05, 120), closeTo(1, 0.01));
  });

  test('a daily player unlocks Candy Corn in two weeks', () {
    // Every plot grows the newest corn. Crops of 12 hours or less are
    // harvested twice a day, longer ones once a day.
    const chain = ['corn', 'crazy_corn', 'super_corn', 'super_crazy_corn'];
    final candyCorn = engine.crop('candy_corn');
    var days = 0;
    for (final cropId in chain) {
      final next = data.garden.crops.firstWhere(
        (crop) => crop.unlockCropId == cropId,
      );
      final perDay = 8 * (engine.crop(cropId).growHours <= 12 ? 2 : 1);
      days += (next.unlockHarvests / perDay).ceil();
      engine.state.garden.harvested[cropId] = next.unlockHarvests;
    }

    expect(engine.isCropUnlocked(candyCorn), isTrue);
    expect(days, 14);
  });

  test('utility crops put the garden-only boost in the boost menu', () {
    final best = engine.boostOptions('best_bird_feed').last;
    expect(best.gardenOnly, isTrue);
    // It can no longer be bought with Golden Eggs.
    engine.state.goldenEggs = 1e9;
    expect(engine.buyBoost('best_bird_feed', best.id), isFalse);
    expect(engine.useGardenBoost('best_bird_feed'), isFalse);

    engine.plantCrop(0, 'feed_grain', 0);
    expect(engine.harvestPlot(0, 24 * _hour), isTrue);
    expect(engine.ownedGardenBoosts('best_bird_feed'), 1);

    expect(engine.useGardenBoost('best_bird_feed'), isTrue);
    expect(engine.ownedGardenBoosts('best_bird_feed'), 0);
    expect(engine.activeBoostMultiplier('earnings'), best.multiplier);
    expect(
      engine.state.activeBoostSeconds['best_bird_feed'],
      best.durationSeconds,
    );
  });

  test('prestige and egg upgrades keep the garden and running boosts', () {
    engine.plantCrop(0, 'soul_root', 0);
    engine.plantCrop(1, 'corn', 0);
    engine.state.garden.boosts['tachyon_prism'] = 2;
    engine.useGardenBoost('tachyon_prism');

    engine.prestige();

    expect(engine.state.garden.planted.keys, [0, 1]);
    expect(engine.ownedGardenBoosts('tachyon_prism'), 1);
    expect(engine.state.activeBoostSeconds['tachyon_prism'], 3600);
  });

  test('harvest all and replant same work across plots', () {
    for (var plot = 0; plot < 3; plot++) {
      engine.plantCrop(plot, 'corn', plot * 30 * _minute);
    }
    // Plot 0 has withered, plot 1 is ready, plot 2 is still growing.
    const now = 6 * _hour + 50 * _minute;

    expect(engine.harvestAll(now), 1);
    expect(engine.state.soulEggs, engine.crop('corn').amount);
    expect(engine.plotStatus(0, now), PlotStatus.empty);
    expect(engine.plotStatus(2, now), PlotStatus.growing);

    expect(engine.replantAll(now), 2);
    expect(engine.plotStatus(0, now), PlotStatus.growing);
    expect(engine.plotStatus(3, now), PlotStatus.empty);
  });

  test('garden time never runs backwards', () {
    final noon = DateTime.utc(2026, 1, 1, 12);
    final now = engine.gardenNow(noon);

    expect(engine.gardenNow(noon.subtract(const Duration(hours: 5))), now);
    expect(
      engine.gardenNow(noon.add(const Duration(hours: 1))),
      now + _hour,
    );
  });

  test('garden data survives a save and old saves load without it', () {
    engine.state.goldenEggs = 100;
    engine.buyPlot();
    engine.plantCrop(8, 'corn', 1234);
    engine.state.garden.harvested['corn'] = 7;
    engine.state.garden.boosts['soul_beacon'] = 3;
    engine.gardenNow(DateTime.utc(2026));

    final json =
        jsonDecode(jsonEncode(engine.state.toJson())) as Map<String, Object?>;
    final restored = GameState.fromJson(json, data).garden;
    expect(restored.extraPlots, 1);
    expect(restored.planted[8]!.cropId, 'corn');
    expect(restored.planted[8]!.plantedAtMs, 1234);
    expect(restored.lastCrops[8], 'corn');
    expect(restored.harvested['corn'], 7);
    expect(restored.boosts['soul_beacon'], 3);
    expect(restored.lastSeenMs, engine.state.garden.lastSeenMs);

    // A save written before the Garden (with its old Prophecy Egg count).
    json
      ..remove('garden')
      ..['prophecyEggs'] = 4;
    final old = GameState.fromJson(json, data);
    expect(old.garden.planted, isEmpty);
    expect(old.garden.extraPlots, 0);
  });

  test('alerts fire when a batch ripens and 15 minutes before it withers', () {
    engine.plantCrop(0, 'corn', 0);
    engine.plantCrop(1, 'corn', 0);
    engine.plantCrop(2, 'feed_grain', 0);

    final alerts = gardenAlerts(engine);

    expect(alerts.map((alert) => alert.atMs), [
      6 * _hour,
      6 * _hour + 30 * _minute,
      24 * _hour,
      24 * _hour + 30 * _minute,
    ]);
    expect(alerts.first.body, contains('2 crops are ready'));
  });
}
