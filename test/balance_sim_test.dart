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

  // Pacing gate. The simulated player holds the hatch button, buys the best
  // payback purchase it can afford and upgrades eggs as soon as it can. It
  // collects no drones, so real play is somewhat faster. Bands are wide on
  // purpose: they catch a broken economy, not small tuning changes.
  test('a fresh farm reaches the first three egg upgrades at a steady pace',
      () {
    final run = _simulate(data, maxEggIndex: 3);
    // ignore: avoid_print
    print(_formatTable(run.secondsPerEgg, data.eggs));

    expect(run.secondsPerEgg, hasLength(3));
    for (final seconds in run.secondsPerEgg) {
      expect(seconds, inInclusiveRange(10 * 60, 30 * 60));
    }
    expect(
      run.secondsPerEgg.reduce((total, seconds) => total + seconds),
      lessThan(75 * 60),
    );
    // About an hour in, a first prestige already pays (wiki Soul Egg formula).
    expect(run.soulEggsGained, greaterThanOrEqualTo(2));
  });

  // Two weeks of a daily player: 30 active minutes a day, the rest offline,
  // prestiging whenever that at least doubles their Soul Eggs. The garden's
  // corn path should be a strong helper without replacing the egg game.
  test('the garden roughly doubles two weeks of Soul Egg progress', () {
    final without = _twoWeeks(data, garden: false);
    final withGarden = _twoWeeks(data, garden: true);
    // ignore: avoid_print
    print(
      'two weeks: ${without.soulEggs} Soul Eggs without the garden, '
      '${withGarden.soulEggs} with it; milestones ${withGarden.rewards}',
    );

    expect(withGarden.rewards, hasLength(4));
    expect(
      withGarden.soulEggs / without.soulEggs,
      inInclusiveRange(1.5, 4),
    );
  });

  test('soul eggs make the next run clearly faster', () {
    final fresh = _simulate(data, maxEggIndex: 1);
    final prestiged = _simulate(data, maxEggIndex: 1, soulEggs: 20);

    expect(
      prestiged.secondsPerEgg.single,
      lessThan(fresh.secondsPerEgg.single * 0.7),
    );
  });
}

({List<double> secondsPerEgg, double soulEggsGained}) _simulate(
  GameData data, {
  int? maxEggIndex,
  double soulEggs = 0,
}) {
  final engine = GameEngine(data: data)..state.soulEggs = soulEggs;
  final secondsPerEgg = <double>[];
  var secondsOnCurrentEgg = 0.0;
  const maxSecondsPerEgg = 2000000.0;

  while (engine.eggIndex + 1 < data.eggs.length &&
      secondsOnCurrentEgg < maxSecondsPerEgg) {
    if (engine.canAscend) {
      secondsPerEgg.add(secondsOnCurrentEgg);
      engine.ascend();
      secondsOnCurrentEgg = 0;
      if (maxEggIndex != null && engine.eggIndex >= maxEggIndex) break;
      continue;
    }

    final candidates = _investmentCandidates(engine);
    final candidate = _bestAffordableInvestment(engine, candidates);
    if (candidate != null) {
      candidate.buy(engine);
      continue;
    }

    final hatchRate = engine.state.hatcheryStock > 0 &&
            engine.state.chickens < engine.totalHabCapacity
        ? engine.holdHatchPerSecond
        : 0.0;
    if (hatchRate > 0) {
      // Same path as the app while the hatch button is held, so the running
      // chicken bonus counts. Drones are not simulated.
      engine.tick(1, refillHatchery: false);
      engine.holdHatch(1, accumulated: 0);
      secondsOnCurrentEgg += 1;
      continue;
    }
    final nextCost = candidates
        .where((item) => item.cost.isFinite && item.cost > engine.state.cash)
        .map((item) => item.cost)
        .fold<double>(double.infinity, math.min);
    final step = _secondsUntilNextEvent(
      engine,
      nextCost,
      hatchRate,
      maxSeconds: maxSecondsPerEgg - secondsOnCurrentEgg,
    );
    if (step == null) break;
    engine.tick(step, manualHatchPerSecond: hatchRate);
    secondsOnCurrentEgg += step;
  }
  return (
    secondsPerEgg: secondsPerEgg,
    soulEggsGained: engine.soulEggsGained,
  );
}

/// Plays [seconds] of active time: hold to hatch, buy the best payback
/// purchase, upgrade eggs, and prestige when it doubles the Soul Eggs held.
void _play(GameEngine engine, double seconds) {
  var remaining = seconds;
  while (remaining > 0) {
    if (engine.soulEggsGained >= math.max(10, engine.state.soulEggs)) {
      engine.prestige();
      continue;
    }
    if (engine.canAscend && engine.ascend()) {
      continue;
    }
    final candidates = _investmentCandidates(engine);
    final candidate = _bestAffordableInvestment(engine, candidates);
    if (candidate != null) {
      candidate.buy(engine);
      continue;
    }
    final hatchRate = engine.state.hatcheryStock > 0 &&
            engine.state.chickens < engine.totalHabCapacity
        ? engine.holdHatchPerSecond
        : 0.0;
    if (hatchRate > 0) {
      engine.tick(1, refillHatchery: false);
      engine.holdHatch(1, accumulated: 0);
      remaining -= 1;
      continue;
    }
    final nextCost = candidates
        .where((item) => item.cost.isFinite && item.cost > engine.state.cash)
        .map((item) => item.cost)
        .fold<double>(double.infinity, math.min);
    final step = math.max(
      1.0,
      _secondsUntilNextEvent(engine, nextCost, 0, maxSeconds: remaining) ??
          remaining,
    );
    engine.tick(step);
    remaining -= step;
  }
}

({double soulEggs, List<String> rewards}) _twoWeeks(
  GameData data, {
  required bool garden,
}) {
  const hour = 3600000;
  final engine = GameEngine(data: data);
  final rewards = <String>[];

  // Seeds are free here: the simulated player always keeps enough cash back.
  void visit(int nowMs, {String? plant}) {
    if (!garden) return;
    engine.harvestAll(nowMs);
    for (final reward in engine.state.garden.newUnlockRewards) {
      rewards.add(
        'day ${nowMs ~/ (24 * hour) + 1} ${reward.cropName} '
        '+${reward.soulEggs}',
      );
    }
    engine.state.garden.newUnlockRewards.clear();
    for (var plot = 0; plant != null && plot < engine.gardenPlotCount; plot++) {
      engine.state.cash += engine.seedCost;
      engine.plantCrop(plot, plant, nowMs);
    }
  }

  for (var day = 0; day < 14; day++) {
    final start = day * 24 * hour;
    // Grow the newest unlocked corn, twice a day when it ripens fast enough.
    if (day > 0) {
      engine.simulateOffline(23.5 * 3600);
    }
    visit(start);
    final crop = data.garden.crops.lastWhere(
      (crop) => crop.reward != 'boost' && engine.isCropUnlocked(crop),
    );
    final growMs = (crop.growHours * hour).round();
    visit(start, plant: crop.id);
    _play(engine, 30 * 60);
    if (crop.growHours <= 12) {
      visit(start + growMs, plant: crop.id);
      if (crop.growHours < 12) {
        visit(start + 2 * growMs);
      }
    } else if (crop.growHours < 24) {
      visit(start + growMs);
    }
  }
  visit(14 * 24 * hour);
  // Count what a prestige right now would add, so both runs compare fairly.
  return (
    soulEggs: engine.state.soulEggs + engine.soulEggsGained,
    rewards: rewards,
  );
}

String _formatTable(List<double> seconds, List<EggData> eggs) {
  return [
    'egg | minutes',
    for (var index = 0; index < seconds.length; index++)
      '${eggs[index + 1].name} | ${(seconds[index] / 60).toStringAsFixed(1)}',
  ].join('\n');
}

double? _secondsUntilNextEvent(
  GameEngine engine,
  double nextCost,
  double hatchRate, {
  required double maxSeconds,
}) {
  bool reachesEvent(double elapsedSeconds) {
    final state = engine.state;
    final originalCash = state.cash;
    final originalChickens = state.chickens;
    final originalStock = state.hatcheryStock;
    final originalPrestigeEarnings = state.cashEarnedThisPrestige;
    final originalRunEarnings = state.cashEarnedThisRun;
    final originalGoldenEggs = state.goldenEggs;
    final originalTrophies = Set<String>.of(state.trophies);
    engine.tick(
      elapsedSeconds,
      manualHatchPerSecond: hatchRate,
    );
    final reached = engine.canAscend || state.cash >= nextCost;
    state.cash = originalCash;
    state.chickens = originalChickens;
    state.hatcheryStock = originalStock;
    state.cashEarnedThisPrestige = originalPrestigeEarnings;
    state.cashEarnedThisRun = originalRunEarnings;
    state.goldenEggs = originalGoldenEggs;
    state.trophies
      ..clear()
      ..addAll(originalTrophies);
    return reached;
  }

  if (!reachesEvent(maxSeconds)) {
    return null;
  }

  var lowerBound = 0.0;
  var upperBound = maxSeconds;
  for (var iteration = 0; iteration < 20; iteration++) {
    final midpoint = (lowerBound + upperBound) / 2;
    if (reachesEvent(midpoint)) {
      upperBound = midpoint;
    } else {
      lowerBound = midpoint;
    }
  }
  return upperBound;
}

_Investment? _bestAffordableInvestment(
  GameEngine engine,
  List<_Investment> candidates,
) {
  final baselineIncome = _projectedIncomeRate(engine);
  final trialEngine = GameEngine(
    data: engine.data,
    state: _copyState(engine.state),
  );
  // When habitats and shipping cap each other, no single purchase raises
  // income; fall back to whatever raises either cap most cheaply.
  final baselinePotential = _projectedIncomeRate(engine, uncapped: true);
  _Investment? best;
  _Investment? bestUnblocker;
  var bestPayback = double.infinity;
  var bestUnblockerPayback = double.infinity;
  for (final candidate in candidates) {
    if (!candidate.cost.isFinite || candidate.cost > engine.state.cash) {
      continue;
    }
    _restoreTrialState(trialEngine.state, engine.state);
    if (!candidate.buy(trialEngine)) {
      continue;
    }
    final incomeIncrease = _projectedIncomeRate(trialEngine) - baselineIncome;
    if (incomeIncrease <= 0) {
      final potentialIncrease =
          _projectedIncomeRate(trialEngine, uncapped: true) - baselinePotential;
      if (potentialIncrease > 0 &&
          candidate.cost / potentialIncrease < bestUnblockerPayback) {
        bestUnblockerPayback = candidate.cost / potentialIncrease;
        bestUnblocker = candidate;
      }
      continue;
    }
    final payback = candidate.cost / incomeIncrease;
    if (payback < bestPayback) {
      bestPayback = payback;
      best = candidate;
    }
  }
  return best ?? bestUnblocker;
}

void _restoreTrialState(GameState target, GameState source) {
  target.cash = source.cash;
  target.cashSpentThisRun = source.cashSpentThisRun;
  target.habs
    ..clear()
    ..addAll(source.habs);
  target.vehicles
    ..clear()
    ..addAll(source.vehicles);
  target.commonResearchLevels
    ..clear()
    ..addAll(source.commonResearchLevels);
}

double _projectedIncomeRate(GameEngine source, {bool uncapped = false}) {
  final engine = source;
  final commonMultipliers = <String, double>{};
  final flatBonuses = <String, double>{};
  for (final item in engine.data.commonResearch) {
    final level = (engine.state.commonResearchLevels[item.id] ?? 0)
        .clamp(0, item.maxLevel)
        .toInt();
    if (level == 0) {
      continue;
    }
    for (final effect in item.effect.split('+')) {
      switch (item.mode) {
        case 'add':
          commonMultipliers.update(
            effect,
            (value) =>
                value *
                (BalanceConfig.baseResearchMultiplier + item.perLevel * level),
            ifAbsent: () =>
                BalanceConfig.baseResearchMultiplier + item.perLevel * level,
          );
          break;
        case 'mul':
          final multiplier = math.pow(item.perLevel, level).toDouble();
          commonMultipliers.update(
            effect,
            (value) => value * multiplier,
            ifAbsent: () => multiplier,
          );
          break;
        case 'flat':
          flatBonuses.update(
            effect,
            (value) => value + item.perLevel * level,
            ifAbsent: () => item.perLevel * level,
          );
          break;
      }
    }
  }
  final epicEffects = <String, double>{};
  for (final item in engine.data.epicResearch) {
    final level = (engine.state.epicResearchLevels[item.id] ?? 0)
        .clamp(0, item.maxLevel)
        .toInt();
    if (level > 0) {
      epicEffects.update(
        item.effect,
        (value) => value + item.perLevel * level,
        ifAbsent: () => item.perLevel * level,
      );
    }
  }
  double commonMultiplier(String effect) =>
      commonMultipliers[effect] ?? BalanceConfig.baseResearchMultiplier;
  double epicMultiplier(String effect) =>
      BalanceConfig.baseResearchMultiplier + (epicEffects[effect] ?? 0);

  final lookahead =
      BalanceConfig.balanceSimulationPaybackLookaheadSeconds.toDouble();
  final habCapacity = engine.state.habs.fold<double>(
    0,
    (capacity, hab) {
      final habData = engine.data.habs[hab.tierIndex];
      final baseMultiplier = math.min(
        habData.maxCapacityMultiplier,
        math.min(
          BalanceConfig.maxBaseHabCapacityMultiplier,
          commonMultiplier('habCapacity'),
        ),
      );
      final portalMultiplier =
          hab.tierIndex >= BalanceConfig.firstPortalHabTierIndex
              ? commonMultiplier('portalHabCapacity')
              : BalanceConfig.baseResearchMultiplier;
      return capacity +
          habData.baseCapacity *
              math.min(
                habData.maxCapacityMultiplier,
                baseMultiplier * portalMultiplier,
              );
    },
  );
  final internalGrowthPerSecond = (flatBonuses['ihrPerHab'] ?? 0) *
      engine.habCount *
      epicMultiplier('ihrMult') /
      BalanceConfig.secondsPerMinute;
  final holdRate =
      BalanceConfig.baseHoldHatchPerSec + (epicEffects['holdHatchPerSec'] ?? 0);
  final refillRate = BalanceConfig.hatcheryRefillPerMin *
      commonMultiplier('hatcheryRefill') *
      epicMultiplier('hatcheryRefill') /
      BalanceConfig.secondsPerMinute;
  final sustainableHoldRate = [
    holdRate,
    refillRate,
  ].reduce((first, second) => first < second ? first : second);
  final expectedHatched = [
    holdRate * lookahead,
    engine.state.hatcheryStock + sustainableHoldRate * lookahead,
  ].reduce((first, second) => first < second ? first : second);
  final startChickens = engine.state.chickens;
  final endChickens = [
    habCapacity,
    startChickens + expectedHatched + internalGrowthPerSecond * lookahead,
  ].reduce((first, second) => first < second ? first : second);
  final projectedChickens = (startChickens + endChickens) / 2;
  var shippingCapacity = 0.0;
  final vehicleMultiplier = commonMultiplier('vehicleCapacity') *
      commonMultiplier('vehicleSpeed') *
      epicMultiplier('vehicleCapacity');
  for (final vehicle in engine.state.vehicles) {
    final vehicleData = engine.data.vehicles[vehicle.tierIndex];
    var multiplier = vehicleMultiplier;
    if (vehicle.tierIndex >= 9) {
      multiplier *= commonMultiplier('hoverVehicleCapacity');
    }
    if (vehicle.tierIndex == 11) {
      multiplier *= commonMultiplier('hyperloopVehicleCapacity');
    }
    shippingCapacity += vehicleData.capacityPerMinute * multiplier;
  }
  final layRateMultiplier =
      commonMultiplier('layRate') * epicMultiplier('layRate');
  final laidPerMinute = projectedChickens *
      BalanceConfig.baseEggsPerChickenPerMinute *
      layRateMultiplier;
  final eggsPerMinute = uncapped
      ? laidPerMinute + shippingCapacity
      : math.min(laidPerMinute, shippingCapacity);
  return eggsPerMinute *
      engine.currentEgg.valuePerEgg *
      commonMultiplier('eggValue') /
      BalanceConfig.secondsPerMinute *
      engine.earningsMultiplier;
}

GameState _copyState(GameState state) => GameState(
      cash: state.cash,
      cashEarnedThisPrestige: state.cashEarnedThisPrestige,
      cashEarnedThisRun: state.cashEarnedThisRun,
      cashSpentThisRun: state.cashSpentThisRun,
      chickens: state.chickens,
      hatcheryStock: state.hatcheryStock,
      goldenEggs: state.goldenEggs,
      soulEggs: state.soulEggs,
      eggIndex: state.eggIndex,
      siloCount: state.siloCount,
      hapticsEnabled: state.hapticsEnabled,
      habs: List.of(state.habs),
      vehicles: List.of(state.vehicles),
      commonResearchLevels: Map.of(state.commonResearchLevels),
      epicResearchLevels: Map.of(state.epicResearchLevels),
      activeBoostSeconds: Map.of(state.activeBoostSeconds),
      activeBoostMultipliers: Map.of(state.activeBoostMultipliers),
      trophies: Set.of(state.trophies),
      piggyBankGoldenEggs: state.piggyBankGoldenEggs,
      runningChickenBatches: List.of(state.runningChickenBatches),
    );

List<_Investment> _investmentCandidates(GameEngine engine) {
  final candidates = <_Investment>[];
  final unlockedTiers = <int, bool>{};
  if (engine.state.habs.length < BalanceConfig.maximumHabCount) {
    for (var slot = 0; slot < BalanceConfig.maximumHabCount; slot++) {
      final cost = engine.habPrice(0, slotIndex: slot);
      if (cost.isFinite) {
        candidates.add(
          _Investment(
            id: 'hab-$slot',
            cost: cost,
            buy: (target) => target.buyHab(0, slotIndex: slot),
          ),
        );
      }
    }
  }
  for (final hab in engine.state.habs) {
    for (var tier = hab.tierIndex + 1; tier < engine.data.habs.length; tier++) {
      final cost = engine.data.habs[tier].slotPrices[hab.slotIndex];
      candidates.add(
        _Investment(
          id: 'hab-${hab.slotIndex}-tier-$tier',
          cost: cost,
          buy: (target) => target.upgradeHab(
            hab.tierIndex,
            hab.slotIndex,
            targetTierIndex: tier,
          ),
        ),
      );
    }
  }
  if (engine.state.vehicles.length < engine.maximumFleetSize) {
    for (var tier = 1; tier < engine.data.vehicles.length; tier++) {
      final unit = engine.state.vehicles
              .where((vehicle) => vehicle.tierIndex == tier)
              .length +
          1;
      candidates.add(
        _Investment(
          id: 'vehicle-$tier',
          cost: engine.vehiclePrice(tier, unit),
          buy: (target) => target.buyVehicle(tier),
        ),
      );
    }
  }
  for (final vehicle in engine.state.vehicles) {
    for (var tier = vehicle.tierIndex + 1;
        tier < engine.data.vehicles.length;
        tier++) {
      candidates.add(
        _Investment(
          id: 'vehicle-${vehicle.slotIndex}-tier-$tier',
          cost: engine.vehicleUpgradePrice(tier),
          buy: (target) =>
              target.upgradeVehicle(vehicle.slotIndex, targetTierIndex: tier),
        ),
      );
    }
  }
  for (final item in engine.data.commonResearch) {
    final level = engine.state.commonResearchLevels[item.id] ?? 0;
    final tier = item.tier;
    if (level < item.maxLevel &&
        tier != null &&
        unlockedTiers.putIfAbsent(
          tier,
          () => engine.isCommonResearchTierUnlocked(tier),
        )) {
      candidates.add(
        _Investment(
          id: item.id,
          cost: engine.commonResearchCost(item.id),
          buy: (target) => target.buyCommonResearch(item.id),
        ),
      );
    }
  }
  return candidates;
}

class _Investment {
  const _Investment({
    required this.id,
    required this.cost,
    required this.buy,
  });

  final String id;
  final double cost;
  final bool Function(GameEngine) buy;
}
