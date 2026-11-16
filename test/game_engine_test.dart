import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:egg_empire/config/balance.dart';
import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/game/engine.dart';

void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await const GameDataLoader().load();
  });

  group('initial game state', () {
    test('starts with one coop, one trike, and a stocked hatchery', () {
      final engine = GameEngine(data: data);

      expect(engine.state.habs, hasLength(1));
      expect(engine.state.habs.single.tierIndex, 0);
      expect(engine.state.vehicles, hasLength(1));
      expect(engine.state.vehicles.single.tierIndex, 0);
      expect(engine.totalHabCapacity, 250);
      expect(engine.hatcheryCapacity, 250);
      expect(engine.state.hatcheryStock, 250);
      expect(engine.maximumFleetSize, 4);
    });
  });

  group('egg ascension and farm value', () {
    test('uses strictly increasing wiki upgrade thresholds', () {
      final thresholds = data.eggs.map((egg) => egg.upgradeFarmValue!).toList();

      expect(thresholds.take(3), [0.0, 68e6, 5.3e9]);
      for (var index = 1; index < thresholds.length; index++) {
        expect(thresholds[index], greaterThan(thresholds[index - 1]));
      }
    });

    test('traverses the complete configurable egg progression', () {
      final engine = GameEngine(data: data);

      expect(data.eggs.length, 19);
      for (var index = 1; index < data.eggs.length; index++) {
        final threshold = engine.nextEggUpgradeFarmValue;
        expect(threshold, isNotNull);
        // Unshipped chickens still count 20% towards farm value.
        engine.state.chickens = threshold!;
        expect(engine.canAscend, isTrue,
            reason: 'before ${data.eggs[index].name}');
        expect(engine.ascend(), isTrue);
        expect(engine.currentEgg.id, data.eggs[index].id);
      }

      expect(engine.nextEggUpgradeFarmValue, isNull);
      expect(engine.canAscend, isFalse);
      expect(engine.ascend(), isFalse);
    });

    test('calculates farm value with the wiki formula', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 100;

      // 500 * L(2) * value(0.25) * lay rate(2) * (Peff + space^0.6).
      expect(
        engine.farmValue,
        closeTo(500 * 2 * 0.25 * 2 * (100 + math.pow(150, 0.6)), 1e-6),
      );
    });

    test('farm value counts unshipped chickens at one fifth', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 10000;

      // The trike ships 5,000 eggs/min, enough for 2,500 chickens.
      expect(engine.farmValue, 500 * 2 * 0.25 * 2 * (0.8 * 2500 + 0.2 * 10000));
    });

    test('silos and internal hatcheries add away hatching to farm value', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 250;
      final before = engine.farmValue;
      engine.state.commonResearchLevels['internal_hatcheries'] = 1;

      expect(engine.farmValue - before, 500 * 2 * 0.25 * 2 * (2 * 1 * 60));
    });

    test('farm value increases after a purchase', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 1000;
      final beforePurchase = engine.farmValue;

      expect(engine.buyHab(0), isTrue);

      expect(engine.farmValue, greaterThan(beforePurchase));
    });

    test('farm value ignores active boost state', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 100;
      final withoutBoosts = engine.farmValue;
      engine.state.activeBoostSeconds['earnings'] = 300;

      expect(engine.incomePerSecondWithoutBoosts, engine.cashPerSecond);
      expect(engine.farmValue, withoutBoosts);
    });

    test('applies Accounting Tricks to the farm value multiplier', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 100;
      final baseValue = engine.farmValue;
      engine.state.epicResearchLevels['accounting_tricks'] = 2;

      expect(engine.farmValue, closeTo(baseValue * 1.1, 1e-9));
    });

    test('ascends at the next egg threshold and resets only run state', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 123;
      engine.state.cashEarnedThisPrestige = 456;
      engine.state.cashEarnedThisRun = 789;
      engine.state.cashSpentThisRun = 1;
      engine.state.chickens = 25;
      engine.state.commonResearchLevels['comfy_nests'] = 1;
      engine.state.siloCount = 3;
      engine.state.activeBoostSeconds['earnings'] = 30;
      engine.state.eggIndex = 0;
      engine.state.chickens = data.eggs[1].upgradeFarmValue!;

      expect(engine.canAscend, isTrue);
      expect(engine.ascend(), isTrue);
      expect(engine.state.eggIndex, 1);
      expect(engine.state.cash, 0);
      expect(engine.state.cashSpentThisRun, 0);
      expect(engine.state.cashEarnedThisRun, 0);
      expect(engine.state.cashEarnedThisPrestige, 456);
      expect(engine.state.chickens, 0);
      expect(engine.state.habs, hasLength(1));
      expect(engine.state.habs.single.tierIndex, 0);
      expect(engine.state.vehicles, hasLength(1));
      expect(engine.state.commonResearchLevels, isEmpty);
      expect(engine.state.siloCount, BalanceConfig.initialSiloCount);
      // Boosts keep running through an egg upgrade.
      expect(engine.state.activeBoostSeconds['earnings'], 30);
    });

    test('does not ascend before the next egg threshold', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 1000;

      expect(engine.canAscend, isFalse);
      expect(engine.ascend(), isFalse);
      expect(engine.state.eggIndex, 0);
    });
  });

  group('habitat purchases', () {
    test('purchases the next open slot and upgrades into the next tier', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 1000;

      expect(engine.habPrice(0), 35.6);
      expect(engine.buyHab(0), isTrue);
      expect(engine.state.habs, hasLength(2));
      expect(engine.state.habs.last.slotIndex, 1);
      expect(engine.state.cash, closeTo(964.4, 1e-9));

      expect(engine.upgradeHab(0, 0), isTrue);
      expect(engine.state.habs.first.tierIndex, 1);
      expect(engine.state.habs.first.slotIndex, 0);
      expect(engine.totalHabCapacity, 750);
      expect(engine.state.cash, closeTo(395.4, 1e-9));
    });

    test('upgrades a habitat in place and preserves its slot', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 10000;

      expect(engine.buyHab(0), isTrue);
      final initialCount = engine.state.habs.length;
      expect(engine.upgradeHab(0, 0), isTrue);
      expect(engine.state.habs, hasLength(initialCount));
      final upgradedHab =
          engine.state.habs.singleWhere((hab) => hab.slotIndex == 0);
      expect(upgradedHab.tierIndex, 1);
      expect(upgradedHab.slotIndex, 0);
    });

    test('can upgrade directly to any higher habitat tier', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 100000;

      expect(engine.upgradeHab(0, 0, targetTierIndex: 2), isTrue);

      final upgradedHab =
          engine.state.habs.singleWhere((hab) => hab.slotIndex == 0);
      expect(upgradedHab.tierIndex, 2);
      expect(engine.state.habs, hasLength(1));
    });

    test('limits the farm to four total habitats across all tiers', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 100000;

      expect(engine.buyHab(0), isTrue);
      expect(engine.buyHab(0), isTrue);
      expect(engine.buyHab(0), isTrue);
      expect(engine.state.habs, hasLength(BalanceConfig.maximumHabCount));
      expect(engine.buyHab(0), isFalse);
      expect(engine.buyHab(1), isFalse);
      expect(engine.habPrice(0), double.infinity);
      expect(engine.habPrice(1), double.infinity);

      expect(engine.upgradeHab(0, 2), isTrue);
      expect(engine.state.habs, hasLength(BalanceConfig.maximumHabCount));
      expect(
          engine.state.habs.singleWhere((hab) => hab.slotIndex == 2).tierIndex,
          1);
    });

    test('rejects unaffordable purchases without mutating state', () {
      final engine = GameEngine(data: data);

      expect(engine.buyHab(0), isFalse);
      expect(engine.state.habs, hasLength(1));
      expect(engine.state.cash, 0);
    });

    test('applies common habitat capacity research within tier caps', () {
      final engine = GameEngine(data: data);
      engine.state.commonResearchLevels.addAll({
        'hen_house_remodel': 8,
        'microlux_suites': 10,
        'grav_plating': 25,
        'wormhole_dampening': 25,
      });

      expect(engine.capacityForHab(0), closeTo(250 * 3.15, 1e-9));
      expect(
        engine.capacityForHab(BalanceConfig.firstPortalHabTierIndex),
        closeTo(100000000 * 4.725, 1e-6),
      );
      expect(engine.capacityForHab(0), lessThanOrEqualTo(250 * 3.15));
    });
  });

  group('vehicle purchases and pricing', () {
    test('interpolates tier curves and extrapolates later unit prices', () {
      final engine = GameEngine(data: data);
      final expectedSecondPrice = 544 * (2.548 + (1.376 - 2.548) / 11);

      expect(engine.vehiclePrice(1, 1), 544);
      expect(engine.vehiclePrice(1, 2), closeTo(expectedSecondPrice, 1e-9));
      expect(engine.vehiclePrice(11, 1), 21.124e36);
      expect(
        engine.vehiclePrice(11, 15),
        closeTo(21.124e36 * 21.22 * 1.2, 1e25),
      );
    });

    test('respects the four-slot fleet limit and charges for purchases', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 10000;

      expect(engine.buyVehicle(1), isTrue);
      expect(engine.state.vehicles.last.unitNumber, 1);
      expect(engine.state.cash, 9456);
      expect(engine.buyVehicle(1), isTrue);
      expect(engine.buyVehicle(1), isTrue);
      expect(engine.state.vehicles, hasLength(4));
      expect(engine.buyVehicle(1), isFalse);
    });

    test('adds fleet slots from flat research', () {
      final engine = GameEngine(data: data);
      engine.state.commonResearchLevels.addAll({
        'vehicle_reliability': 2,
        'exoskeletons': 2,
        'traffic_management': 2,
        'egg_bots': 2,
        'autonomous_vehicles': 5,
      });

      expect(engine.maximumFleetSize, 17);
    });

    test('upgrades one vehicle in place to any higher tier', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 1e40;
      engine.state.vehicles.add(const VehicleOwnership(1, 1, 1));

      expect(
        engine.upgradeVehicle(1, targetTierIndex: 11),
        isTrue,
      );

      final upgraded = engine.state.vehicles
          .singleWhere((vehicle) => vehicle.slotIndex == 1);
      expect(upgraded.tierIndex, 11);
      expect(upgraded.unitNumber, 1);
      expect(engine.state.vehicles, hasLength(2));
      expect(engine.state.cash, lessThan(1e40));
    });

    test('buys a vehicle in the selected empty fleet slot', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 100000;

      expect(engine.buyVehicle(2, slotIndex: 3), isTrue);
      expect(engine.state.vehicles.last.slotIndex, 3);
      expect(engine.buyVehicle(1, slotIndex: 3), isFalse);
      expect(engine.buyVehicle(1, slotIndex: 4), isFalse);
    });
  });

  group('hatchery and internal hatcheries', () {
    test('hatches only available stock and habitat room', () {
      final engine = GameEngine(data: data);

      expect(engine.hatch(requested: 300), 250);
      expect(engine.state.chickens, 250);
      expect(engine.state.hatcheryStock, 0);
      expect(engine.hatch(), 0);

      engine.state.cash = 100;
      expect(engine.buyHab(0), isTrue);
      expect(engine.hatch(requested: 300), 0);
      engine.tick(60);
      expect(engine.state.hatcheryStock, 250);
    });

    group('common research purchases', () {
      test('reads wiki costs and purchases one level at a time', () {
        final engine = GameEngine(data: data);
        final item = data.commonResearch.firstWhere(
          (research) => research.id == 'comfy_nests',
        );
        engine.state.cash = 1000;

        expect(engine.commonResearchCost(item.id), 0.502606);
        expect(engine.buyCommonResearch(item.id), isTrue);
        expect(engine.state.commonResearchLevels[item.id], 1);
        expect(engine.state.cash, closeTo(1000 - 0.502606, 1e-9));
        expect(engine.state.cashSpentThisRun, 0.502606);
        expect(engine.layRateMultiplier, 1.1);
        expect(engine.commonResearchCost(item.id), 3.25839);

        engine.state.epicResearchLevels['lab_upgrade'] = 10;
        expect(engine.commonResearchCost(item.id), closeTo(3.25839 / 2, 1e-9));
      });

      test('locks higher tiers until the earlier-tier level threshold is met',
          () {
        final engine = GameEngine(data: data);
        engine.state.cash = 100000;

        expect(engine.isCommonResearchTierUnlocked(1), isTrue);
        expect(engine.isCommonResearchTierUnlocked(2), isFalse);
        expect(engine.buyCommonResearch('internal_hatcheries'), isFalse);

        engine.state.commonResearchLevels['comfy_nests'] = 30;

        expect(engine.isCommonResearchTierUnlocked(2), isTrue);
        expect(engine.buyCommonResearch('internal_hatcheries'), isTrue);
        expect(engine.flatResearchBonus('ihrPerHab'), 2);
      });

      test('uses the single-level last cost and rejects exhausted levels', () {
        final engine = GameEngine(data: data);
        engine.state.commonResearchLevels['comfy_nests'] = 30;
        engine.state.cash = 2000000;

        expect(engine.commonResearchCost('bigger_eggs'), 1351900);
        expect(engine.buyCommonResearch('bigger_eggs'), isTrue);
        expect(engine.state.commonResearchLevels['bigger_eggs'], 1);
        expect(engine.commonResearchCost('bigger_eggs'), double.infinity);
        expect(engine.buyCommonResearch('bigger_eggs'), isFalse);
      });
    });

    test('grows chickens using internal hatchery research per hab', () {
      final engine = GameEngine(data: data);
      engine.state.commonResearchLevels['internal_hatcheries'] = 10;

      engine.tick(60);

      expect(engine.state.chickens, 20);
      expect(engine.state.habs, hasLength(1));
    });

    test('sums all common internal-hatchery research at its maximum', () {
      final engine = GameEngine(data: data);
      for (final item in data.commonResearch) {
        if (item.effect == 'ihrPerHab') {
          engine.state.commonResearchLevels[item.id] = item.maxLevel;
        }
      }

      expect(engine.flatResearchBonus('ihrPerHab'), 3720);
    });
  });

  group('economy formulas and fixed ticker', () {
    test('limits shipped eggs and cash to the shipping bottleneck', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 10000;

      expect(engine.eggsLaidPerMinute, 20000);
      expect(engine.shipCapacityPerMinute, 5000);
      expect(engine.eggsShippedPerMinute, 5000);
      expect(engine.eggsBackingUp, isTrue);
      expect(engine.cashPerSecond, closeTo(5000 / 60 * 0.25, 1e-9));
    });

    test('compounds research, including Improved Genetics on both stats', () {
      final engine = GameEngine(data: data);
      engine.state.commonResearchLevels.addAll({
        'comfy_nests': 10,
        'nutritional_supplements': 4,
        'bigger_eggs': 1,
        'improved_genetics': 2,
      });

      expect(engine.layRateMultiplier, closeTo(2 * 1.3, 1e-9));
      expect(engine.eggValueMultiplier, closeTo(2 * 2 * 1.3, 1e-9));
    });

    test('credits earned cash and accumulates fixed real-time updates', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 120;
      final ticker = GameTicker(engine);

      expect(ticker.advance(0.05), 0);
      expect(ticker.advance(0.05), 1);
      expect(ticker.advance(0.25), 2);
      expect(engine.state.cash, closeTo(0.3, 1e-9));
      expect(engine.state.cashEarnedThisPrestige, engine.state.cash);
      expect(engine.state.cashEarnedThisRun, engine.state.cash);
    });
  });

  group('prestige, epic research, and trophies', () {
    test('calculates Soul Egg gain with the wiki earnings bands', () {
      final engine = GameEngine(data: data);
      engine.state.cashEarnedThisPrestige = 1e12;
      // (1e6)^0.15 - (1e-6)^0.15 = 7.817
      expect(engine.soulEggsGained, 7);

      engine.state.epicResearchLevels['prestige_bonus'] = 2;
      expect(engine.soulEggsGained, 9);

      engine.state.epicResearchLevels.clear();
      engine.state.cashEarnedThisPrestige = 1e21;
      // Adds the second band: (1e15)^0.16 - (1e6)^0.16 = 242.07
      expect(engine.soulEggsGained, 249);
    });

    test('Soul Beacon multiplies the earnings fed into prestige', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 120;
      engine.state.activeBoostSeconds['soul_beacon'] = 30;
      engine.state.activeBoostMultipliers['soul_beacon'] = 5;

      engine.tick(1);

      expect(engine.state.cash, closeTo(1, 1e-9));
      expect(engine.state.cashEarnedThisPrestige, closeTo(5, 1e-9));
    });

    test('builds a second silo at the wiki price and stops at the cap', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 100000;

      expect(engine.nextSiloPrice, 100000);
      expect(engine.buySilo(), isTrue);
      expect(engine.state.siloCount, 2);
      expect(engine.nextSiloPrice, double.infinity);
      expect(engine.buySilo(), isFalse);
    });

    test('compounds earnings bonus with harvested Candy Corn', () {
      final engine = GameEngine(data: data);
      engine.state.soulEggs = 100;

      expect(engine.earningsBonus, 10);
      expect(engine.earningsMultiplier, 11);

      // 8 plots a day for a year is worth about 120 Prophecy Eggs.
      engine.state.garden.harvested['candy_corn'] = 8 * 365;
      expect(engine.gardenBonusUnits, closeTo(120, 0.1));
      expect(
        engine.earningsBonus,
        closeTo(10 * math.pow(1.05, engine.gardenBonusUnits), 1e-6),
      );

      engine.state.epicResearchLevels['prophecy_bonus'] = 5;
      expect(engine.prophecyEggMultiplier, 1.10);
      expect(
        engine.earningsBonus,
        closeTo(10 * math.pow(1.10, engine.gardenBonusUnits), 1e-3),
      );
    });

    test('applies earnings bonus to cash income', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 100;
      final baseIncome = engine.cashPerSecond;
      engine.state.soulEggs = 100;

      expect(engine.cashPerSecond, closeTo(baseIncome * 11, 1e-9));
    });

    test('buys epic research with Golden Eggs and caps its level', () {
      final engine = GameEngine(data: data);
      engine.state.goldenEggs = 10;

      expect(engine.epicResearchCost('soul_food'), 5);
      expect(engine.buyEpicResearch('soul_food'), isTrue);
      expect(engine.state.goldenEggs, 5);
      expect(engine.epicResearchLevel('soul_food'), 1);
      expect(engine.epicResearchCost('soul_food'), greaterThan(5));

      engine.state.epicResearchLevels['soul_food'] = 140;
      expect(engine.epicResearchCost('soul_food'), double.infinity);
      expect(engine.buyEpicResearch('soul_food'), isFalse);
    });

    test('prestige resets the run and preserves permanent progress', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 123;
      engine.state.cashEarnedThisPrestige = 10000000;
      engine.state.cashEarnedThisRun = 456;
      engine.state.cashSpentThisRun = 789;
      engine.state.chickens = 25;
      engine.state.goldenEggs = 50;
      engine.state.garden.harvested['corn'] = 2;
      engine.state.eggIndex = 3;
      engine.state.commonResearchLevels['comfy_nests'] = 1;
      engine.state.epicResearchLevels['soul_food'] = 4;
      engine.state.trophies.add('edible:trophy:2');
      engine.state.activeBoostSeconds['best_bird_feed'] = 300;

      final gained = engine.prestige();

      expect(gained, 1);
      expect(engine.state.soulEggs, 1);
      expect(engine.state.eggIndex, 0);
      expect(engine.state.cash, 0);
      expect(engine.state.cashEarnedThisPrestige, 0);
      expect(engine.state.cashEarnedThisRun, 0);
      expect(engine.state.cashSpentThisRun, 0);
      expect(engine.state.chickens, 0);
      expect(engine.state.hatcheryStock, BalanceConfig.baseHatcheryCapacity);
      expect(engine.state.habs.single.tierIndex, 0);
      expect(engine.state.vehicles.single.tierIndex, 0);
      expect(engine.state.commonResearchLevels, isEmpty);
      // Boosts and the garden carry over a prestige.
      expect(engine.state.activeBoostSeconds['best_bird_feed'], 300);
      expect(engine.state.goldenEggs, 50);
      expect(engine.state.garden.harvested['corn'], 2);
      expect(engine.epicResearchLevel('soul_food'), 4);
      expect(engine.state.trophies, contains('edible:trophy:2'));
    });

    test('awards exact edible trophy rewards only once', () {
      final engine = GameEngine(data: data);
      engine.state.habs
        ..clear()
        ..addAll([
          const HabOwnership(18, 0),
          const HabOwnership(18, 1),
          const HabOwnership(18, 2),
          const HabOwnership(18, 3),
        ]);
      for (final item in data.commonResearch) {
        if (item.effect.contains('habCapacity') ||
            item.effect.contains('portalHabCapacity')) {
          engine.state.commonResearchLevels[item.id] = item.maxLevel;
        }
      }
      engine.state.chickens = 10e9;

      engine.tick(1);

      expect(engine.state.trophies, hasLength(5));
      expect(engine.state.soulEggs, 10.112e9);

      engine.tick(1);

      expect(engine.state.trophies, hasLength(5));
      expect(engine.state.soulEggs, 10.112e9);
    });

    test('uses the five fixed wiki chicken-count thresholds', () {
      final engine = GameEngine(data: data);

      expect(
        List<double>.generate(
          BalanceConfig.trophyChickenCountThresholds.length,
          engine.trophyChickenCountThreshold,
        ),
        [10e6, 50e6, 250e6, 1e9, 10e9],
      );
    });

    test('stores wiki rewards by egg and trophy tier', () {
      expect(
        BalanceConfig.trophySoulEggRewards['superfood'],
        [1e6, 5e6, 50e6, 2.5e9],
      );
      expect(
        BalanceConfig.trophyGoldenEggRewards['cinder'],
        [3e3, 4e3, 5e3, 10e3, 25e3],
      );
    });
  });

  group('running chicken bonus and Piggy Bank', () {
    test('manual hatch increases income but not stable farm value', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 100;
      engine.hatch(requested: 10);
      final stableFarmValue = engine.farmValue;
      final stableIncome = engine.incomePerSecondWithoutBoosts;

      expect(engine.runningChickenCount, 10);
      const bonus = 1 + 10 * BalanceConfig.runningChickenBonusPerChicken;
      expect(engine.runningChickenMultiplier, bonus);
      expect(engine.cashPerSecond, closeTo(stableIncome * bonus, 1e-9));
      expect(engine.farmValue, stableFarmValue);

      engine.tick(BalanceConfig.runningChickenDurationSeconds);
      expect(engine.runningChickenCount, 0);
      expect(engine.runningChickenMultiplier, 1);
    });

    test('caps running bonus using common and epic max-bonus research', () {
      final engine = GameEngine(data: data);
      engine.state.runningChickenBatches.add(
        const RunningChickenBatch(chickens: 10000, secondsRemaining: 10),
      );

      expect(
        engine.runningChickenMultiplier,
        BalanceConfig.baseMaximumRunningChickenBonus,
      );

      engine.state.commonResearchLevels['coordinated_clucking'] = 50;
      engine.state.epicResearchLevels['epic_multiplier'] = 1;
      expect(
        engine.maximumRunningChickenBonus,
        greaterThan(BalanceConfig.baseMaximumRunningChickenBonus),
      );
      expect(
        engine.runningChickenMultiplier,
        engine.maximumRunningChickenBonus,
      );
    });

    test('running bonus is inactive when habitats are full', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = engine.totalHabCapacity;
      engine.state.runningChickenBatches.add(
        const RunningChickenBatch(chickens: 100, secondsRemaining: 10),
      );

      expect(engine.runningChickenMultiplier, 1);
      expect(engine.cashPerSecond, engine.incomePerSecondWithoutBoosts);
    });

    test('Piggy Bank accrues on purchases and can be cracked', () {
      final engine = GameEngine(data: data);
      engine.state.cash = 1000;
      engine.state.goldenEggs = 100;

      expect(engine.buyHab(0), isTrue);
      expect(
          engine.state.piggyBankGoldenEggs, BalanceConfig.piggyBankHabReward);
      expect(engine.buyCommonResearch('comfy_nests'), isTrue);
      expect(
        engine.state.piggyBankGoldenEggs,
        BalanceConfig.piggyBankHabReward +
            BalanceConfig.piggyBankResearchReward,
      );
      expect(
        engine.buyBoost(
          'best_bird_feed',
          engine.boostOptions('best_bird_feed').first.id,
        ),
        isTrue,
      );
      final expectedStored = BalanceConfig.piggyBankHabReward +
          BalanceConfig.piggyBankResearchReward +
          BalanceConfig.piggyBankBoostReward;
      expect(engine.crackPiggyBank(), isTrue);
      expect(
          engine.state.goldenEggs, closeTo(100 - 0.5 + expectedStored, 1e-9));
      expect(engine.state.piggyBankGoldenEggs, 0);
      expect(engine.crackPiggyBank(), isFalse);
    });
  });

  group('drones and boosts', () {
    test('drone cash rewards use farm value and credit farm earnings', () {
      final engine = GameEngine(data: data);
      engine.state.chickens = 100;
      final expected =
          engine.farmValue * BalanceConfig.droneCashRewardFractions.last;

      final reward = engine.collectDrone(
        rewardRoll: 0.9,
        tierRoll: 0.99,
        eliteRoll: 0.5,
        speed: 0,
      );

      expect(reward.isGoldenEggReward, isFalse);
      expect(reward.goldenEggs, 0);
      expect(reward.cash, expected);
      expect(engine.state.cash, expected);
      expect(engine.state.cashEarnedThisPrestige, expected);
      expect(engine.state.cashEarnedThisRun, expected);
    });

    test('regular and elite drone Golden Egg rewards follow configured tiers',
        () {
      final engine = GameEngine(data: data);

      final regular = engine.collectDrone(
        rewardRoll: 0.1,
        tierRoll: 0.99,
        eliteRoll: 0.5,
        speed: 0,
      );
      final elite = engine.collectDrone(
        rewardRoll: 0.9,
        tierRoll: 0.99,
        eliteRoll: 0,
        speed: 0,
      );

      expect(regular.goldenEggs, 12);
      expect(regular.isElite, isFalse);
      expect(elite.goldenEggs, 48);
      expect(elite.isElite, isTrue);
      expect(engine.state.goldenEggs, 60);
    });

    test('Drone Rewards epic research shifts reward weight upward', () {
      final engine = GameEngine(data: data);
      engine.state.epicResearchLevels['drone_rewards'] = 20;

      final reward = engine.collectDrone(
        rewardRoll: 0.1,
        tierRoll: 0.9,
        eliteRoll: 0.5,
        speed: 0,
      );

      expect(reward.goldenEggs, 12);
    });

    test('buys boost tiers, applies Boost Beacon, and expires timers', () {
      final engine = GameEngine(data: data);
      engine.state.goldenEggs = 1000;
      engine.state.chickens = 100;
      final baseIncome = engine.cashPerSecond;
      // Cheapest tiers: feed x3 for 20 minutes, beacon x2 for 30 minutes.
      final feedOption = engine.boostOptions('best_bird_feed').first;
      final beaconOption = engine.boostOptions('boost_beacon').first;

      expect(engine.buyBoost('best_bird_feed', feedOption.id), isTrue);
      expect(engine.cashPerSecond, closeTo(baseIncome * 3, 1e-9));
      expect(engine.buyBoost('boost_beacon', beaconOption.id), isTrue);
      expect(engine.cashPerSecond, closeTo(baseIncome * 6, 1e-9));
      expect(engine.state.goldenEggs, closeTo(1000 - 0.5 - 10, 1e-9));

      engine.tick(2000);

      expect(engine.state.activeBoostSeconds, isEmpty);
      expect(engine.state.activeBoostMultipliers, isEmpty);
      expect(engine.cashPerSecond, baseIncome);
      expect(engine.state.cash, closeTo(baseIncome * (1200 * 6 + 800), 1e-6));
    });

    test('Tachyon boost multiplies internal hatchery growth', () {
      final baseline = GameEngine(data: data);
      baseline.state.habs.add(const HabOwnership(1, 1));
      baseline.state.commonResearchLevels['internal_hatcheries'] = 10;

      final engine = GameEngine(data: data);
      engine.state.habs.add(const HabOwnership(1, 1));
      engine.state.commonResearchLevels['internal_hatcheries'] = 10;
      engine.state.goldenEggs = 100;
      final option = engine.boostOptions('tachyon_prism').first;

      expect(engine.buyBoost('tachyon_prism', option.id), isTrue);
      engine.tick(60, refillHatchery: false);
      baseline.tick(60, refillHatchery: false);

      expect(
        engine.state.chickens,
        closeTo(baseline.state.chickens * 10, 1e-9),
      );
    });

    test('boost levels and timers survive save-state JSON round-trip', () {
      final engine = GameEngine(data: data);
      final option = engine.boostOptions('best_bird_feed').first;
      engine.state.goldenEggs = 100;
      expect(engine.buyBoost('best_bird_feed', option.id), isTrue);

      final restored = GameState.fromJson(engine.state.toJson(), data);
      final restoredEngine = GameEngine(data: data, state: restored);

      expect(
        restoredEngine.activeBoostMultiplier('earnings'),
        3,
      );
      expect(
        restored.activeBoostSeconds['best_bird_feed'],
        engine.state.activeBoostSeconds['best_bird_feed'],
      );
    });
  });
}
