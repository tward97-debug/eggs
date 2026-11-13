import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:egg_empire/config/balance.dart';
import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/game/engine.dart';

void main() {
  test('runs a bounded balance diagnostic without tuning values', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await const GameDataLoader().load();
    final watch = Stopwatch()..start();
    final secondsPerEgg = _simulate(
      data,
      const FarmValueTuning.configured(),
      maxEggIndex: 1,
    );
    watch.stop();
    // ignore: avoid_print
    print('simulation runtime=${watch.elapsedMilliseconds}ms');
    // ignore: avoid_print
    print(_formatTable(secondsPerEgg, data.eggs));
    expect(secondsPerEgg, isNotEmpty);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

List<double> _simulate(
  GameData data,
  FarmValueTuning tuning, {
  int? maxEggIndex,
}) {
  final engine = GameEngine(data: data, farmValueTuning: tuning);
  final secondsPerEgg = <double>[];
  var secondsOnCurrentEgg = 0.0;
  var purchaseCount = 0;
  var totalPurchaseCount = 0;
  final wallWatch = Stopwatch()..start();
  const maxSecondsPerEgg = 2000000.0;

  while (engine.eggIndex + 1 < data.eggs.length &&
      secondsOnCurrentEgg < maxSecondsPerEgg) {
    if (engine.canAscend) {
      secondsPerEgg.add(secondsOnCurrentEgg);
      // ignore: avoid_print
      print(
        'diagnostic egg=${engine.eggIndex + 1} purchases=$purchaseCount '
        'wall=${wallWatch.elapsedMilliseconds}ms',
      );
      totalPurchaseCount += purchaseCount;
      purchaseCount = 0;
      engine.ascend();
      secondsOnCurrentEgg = 0;
      if (maxEggIndex != null && engine.eggIndex >= maxEggIndex) break;
      continue;
    }

    final candidates = _investmentCandidates(engine);
    final candidate = _bestAffordableInvestment(engine, candidates);
    if (candidate != null) {
      candidate.buy(engine);
      purchaseCount++;
      continue;
    }

    final hatchRate = engine.state.hatcheryStock > 0 &&
            engine.state.chickens < engine.totalHabCapacity
        ? engine.holdHatchPerSecond
        : 0.0;
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
  // ignore: avoid_print
  print('diagnostic total purchases=$totalPurchaseCount');
  return secondsPerEgg;
}

String _formatTable(List<double> seconds, List<EggData> eggs) {
  final rows = <String>[
    'egg | seconds | ratio to previous | pass/fail',
    '--- | ---: | ---: | :---:',
  ];
  var allPass = seconds.isNotEmpty &&
      seconds.first.isFinite &&
      seconds.first >= 240 &&
      seconds.first <= 600;
  for (var index = 0; index < seconds.length; index++) {
    final elapsed = seconds[index];
    final ratio = index == 0 ? null : elapsed / seconds[index - 1];
    final passes = elapsed.isFinite &&
        (index == 0
            ? elapsed >= 240 && elapsed <= 600
            : elapsed > seconds[index - 1] && ratio! >= 1.5 && ratio <= 3.0);
    allPass &= passes;
    rows.add(
      '${eggs[index + 1].name} | ${_formatSeconds(elapsed)} | '
      '${ratio == null ? "—" : ratio.toStringAsFixed(2)} | '
      '${passes ? "PASS" : "FAIL"}',
    );
  }
  return '${rows.join('\n')}\nOverall: ${allPass ? "PASS" : "FAIL"}';
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
    final originalProphecyEggs = state.prophecyEggs;
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
    state.prophecyEggs = originalProphecyEggs;
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

String _formatSeconds(double seconds) =>
    seconds.isFinite ? seconds.toStringAsFixed(0) : 'not reached';

_Investment? _bestAffordableInvestment(
  GameEngine engine,
  List<_Investment> candidates,
) {
  final baselineIncome = _projectedIncomeRate(engine);
  final trialEngine = GameEngine(
    data: engine.data,
    state: _copyState(engine.state),
    farmValueTuning: engine.farmValueTuning,
  );
  _Investment? best;
  var bestPayback = double.infinity;
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
      continue;
    }
    final payback = candidate.cost / incomeIncrease;
    if (payback < bestPayback) {
      bestPayback = payback;
      best = candidate;
    }
  }
  return best;
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

double _projectedIncomeRate(GameEngine source) {
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
  final eggsPerMinute = math.min(
    projectedChickens *
        BalanceConfig.baseEggsPerChickenPerMinute *
        layRateMultiplier,
    shippingCapacity,
  );
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
      prophecyEggs: state.prophecyEggs,
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
