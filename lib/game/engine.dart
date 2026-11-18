import 'dart:math' as math;

import '../config/balance.dart';
import 'garden.dart';
export 'garden.dart';
import 'models/game_data.dart';

class DroneReward {
  const DroneReward({
    required this.goldenEggs,
    required this.cash,
    required this.isElite,
    required this.isGoldenEggReward,
  });

  final double goldenEggs;
  final double cash;
  final bool isElite;
  final bool isGoldenEggReward;
}

class RunningChickenBatch {
  const RunningChickenBatch({
    required this.chickens,
    required this.secondsRemaining,
  });

  final double chickens;
  final double secondsRemaining;

  RunningChickenBatch elapse(double seconds) => RunningChickenBatch(
        chickens: chickens,
        secondsRemaining: secondsRemaining - seconds,
      );
}

class GameEngine {
  GameEngine({
    required this.data,
    GameState? state,
  }) : state = state ?? GameState.newGame();

  final GameData data;
  final GameState state;

  int get eggIndex => state.eggIndex;

  EggData get currentEgg => data.eggs[state.eggIndex];

  /// Uses the older wiki base capacity plus flat hatchery-capacity research.
  double get hatcheryCapacity =>
      BalanceConfig.baseHatcheryCapacity +
      flatResearchBonus('hatcheryCapacity');

  /// Uses the tunable refill rate multiplied by common refill research.
  double get hatcheryRefillPerMinute =>
      BalanceConfig.hatcheryRefillPerMin *
      researchMultiplier('hatcheryRefill') *
      epicResearchMultiplier('hatcheryRefill');

  double get holdHatchPerSecond =>
      BalanceConfig.baseHoldHatchPerSec + epicResearchEffect('holdHatchPerSec');

  /// Uses the starting fleet slots plus flat common fleet-size research.
  double get maximumFleetSize =>
      BalanceConfig.baseFleetSize + flatResearchBonus('fleetSize');

  /// Returns the number of owned habitats used for internal hatchery growth.
  double get habCount => state.habs.length.toDouble();

  /// Sums each habitat's capacity after applicable common capacity research.
  double get totalHabCapacity => state.habs.fold<double>(
        0,
        (capacity, hab) => capacity + capacityForHab(hab.tierIndex),
      );

  /// Multiplies the common lay-rate research factors from the research data.
  double get layRateMultiplier =>
      researchMultiplier('layRate') * epicResearchMultiplier('layRate');

  /// Multiplies common egg-value research factors from the research data.
  double get eggValueMultiplier => researchMultiplier('eggValue');

  /// Applies the spec's vehicle-speed-as-shipping-capacity assumption.
  double get vehicleCapacityMultiplier =>
      researchMultiplier('vehicleCapacity') *
      researchMultiplier('vehicleSpeed') *
      epicResearchMultiplier('vehicleCapacity');

  /// Uses the wiki base rate of two eggs per chicken per minute.
  double get eggsLaidPerMinute =>
      state.chickens *
      BalanceConfig.baseEggsPerChickenPerMinute *
      layRateMultiplier;

  /// Sums owned vehicle capacities after applicable research multipliers.
  double get shipCapacityPerMinute => state.vehicles.fold<double>(
        0,
        (capacity, vehicle) => capacity + capacityForVehicle(vehicle.tierIndex),
      );

  double capacityForVehicle(int tierIndex) {
    _checkIndex(tierIndex, data.vehicles.length, 'vehicle tier');
    var multiplier = vehicleCapacityMultiplier;
    if (tierIndex >= 9) {
      multiplier *= researchMultiplier('hoverVehicleCapacity');
    }
    if (tierIndex == 11) {
      multiplier *= researchMultiplier('hyperloopVehicleCapacity');
    }
    return data.vehicles[tierIndex].capacityPerMinute * multiplier;
  }

  /// Applies the shipping bottleneck before valuing eggs at the current egg.
  double get eggsShippedPerMinute =>
      math.min(eggsLaidPerMinute, shipCapacityPerMinute);

  /// Converts shipped eggs per minute to cash per second using egg research.
  double get cashPerSecond =>
      incomePerSecondWithoutBoosts *
      runningChickenMultiplier *
      activeBoostMultiplier('earnings');

  /// PLACEHOLDER bonus from manually hatched chickens still in their run window.
  double get runningChickenCount => state.runningChickenBatches.fold<double>(
        0,
        (total, batch) => total + batch.chickens,
      );

  double get maximumRunningChickenBonus =>
      BalanceConfig.baseMaximumRunningChickenBonus +
      flatResearchBonus('maxRunningBonus') +
      epicResearchEffect('maxRunningBonus');

  double get runningChickenMultiplier {
    if (state.chickens >= totalHabCapacity) {
      return 1;
    }
    return math
        .min(
          1 + runningChickenCount * runningChickenBonusPerChicken,
          maximumRunningChickenBonus,
        )
        .toDouble();
  }

  double get runningChickenBonusPerChicken =>
      BalanceConfig.runningChickenBonusPerChicken +
      epicResearchEffect('runningBonusPerChicken');

  /// Computes stable income without active boosts for farm value.
  double get incomePerSecondWithoutBoosts =>
      (eggsShippedPerMinute / BalanceConfig.secondsPerMinute) *
      currentEgg.valuePerEgg *
      eggValueMultiplier *
      earningsMultiplier;

  /// Linear Soul Egg bonus, compounded by the Garden's Candy Corn the way
  /// Prophecy Eggs compound it in the original.
  double get perSoulEggEarningsBonus =>
      BalanceConfig.basePerSoulEggEarningsBonus +
      epicResearchEffect('soulFood');

  double get prophecyEggMultiplier =>
      BalanceConfig.baseProphecyEggMultiplier +
      epicResearchEffect('prophecyBonus');

  double get earningsBonus {
    return state.soulEggs *
        perSoulEggEarningsBonus *
        math.pow(prophecyEggMultiplier, gardenBonusUnits).toDouble();
  }

  /// Converts the compounding earnings bonus into the cash-rate multiplier.
  double get earningsMultiplier =>
      BalanceConfig.baseEarningsMultiplier + earningsBonus;

  /// Returns the active Soul Beacon multiplier, or one when it is inactive.
  double get activeSoulBeaconMultiplier {
    return activeBoostMultiplier('soulEggGain');
  }

  /// Returns an active boost factor, including any active Boost Beacon.
  double activeBoostMultiplier(String effect) {
    final boost =
        data.boosts.where((item) => item.effect == effect).firstOrNull;
    if (boost == null || (state.activeBoostSeconds[boost.id] ?? 0) <= 0) {
      return 1;
    }
    final multiplier = state.activeBoostMultipliers[boost.id] ?? 1;
    if (effect == 'boostBeacon') {
      return multiplier;
    }
    return multiplier * _activeBoostById('boost_beacon');
  }

  double _activeBoostById(String id) {
    final boost = data.boosts.where((item) => item.id == id).firstOrNull;
    if (boost == null || (state.activeBoostSeconds[id] ?? 0) <= 0) {
      return 1;
    }
    return state.activeBoostMultipliers[id] ?? 1;
  }

  /// Lists the data-defined tiers of a boost with scaled Golden Egg prices.
  List<BoostOption> boostOptions(String boostId) => _boostItem(boostId).options;

  /// Spends Golden Eggs and starts or refreshes one boost of its effect.
  bool buyBoost(String boostId, String optionId) {
    final option = boostOptions(boostId)
        .where((candidate) => candidate.id == optionId)
        .firstOrNull;
    if (option == null || option.gardenOnly) {
      return false;
    }
    final price = boostPrice(option);
    if (state.goldenEggs < price) {
      return false;
    }
    state.goldenEggs -= price;
    _addPiggyBankGoldenEggs(BalanceConfig.piggyBankBoostReward);
    state.activeBoostSeconds[boostId] = option.durationSeconds;
    state.activeBoostMultipliers[boostId] = option.multiplier;
    return true;
  }

  double boostPrice(BoostOption option) =>
      option.priceGoldenEggs * BalanceConfig.goldenEggCostScale;

  /// Rolls and credits a drone reward; each roll input is deterministic/testable.
  DroneReward collectDrone({
    required double rewardRoll,
    required double tierRoll,
    required double eliteRoll,
    required double speed,
  }) {
    _validateDroneRoll(rewardRoll, 'rewardRoll');
    _validateDroneRoll(tierRoll, 'tierRoll');
    _validateDroneRoll(eliteRoll, 'eliteRoll');
    if (!speed.isFinite || speed < 0 || speed > 1) {
      throw ArgumentError.value(speed, 'speed', 'Must be in [0, 1].');
    }

    final isElite = eliteRoll < BalanceConfig.droneEliteChance;
    final isGoldenEggReward =
        isElite || rewardRoll < BalanceConfig.droneGoldenEggChance;
    final epicShift = epicResearchEffect('droneBigRewardChance') *
        BalanceConfig.droneEpicWeightShiftPerEffect;
    final speedShift = speed * BalanceConfig.droneFastTapMaxWeightShift;
    final shift = epicShift + speedShift;
    if (!isGoldenEggReward) {
      final reward = DroneReward(
        goldenEggs: 0,
        cash: cashPerSecond * BalanceConfig.droneCashRewardEarningsSeconds,
        isElite: false,
        isGoldenEggReward: false,
      );
      _creditCash(reward.cash);
      return reward;
    }

    final rewards = isElite
        ? BalanceConfig.eliteDroneGoldenEggRewards
        : BalanceConfig.droneGoldenEggRewards;
    final weights = _shiftDroneWeights(
      isElite
          ? BalanceConfig.eliteDroneTierWeights
          : BalanceConfig.droneGoldenEggTierWeights,
      shift,
    );
    final rewardIndex = _weightedIndex(weights, tierRoll);
    final reward = DroneReward(
      goldenEggs: rewards[rewardIndex],
      cash: 0,
      isElite: isElite,
      isGoldenEggReward: true,
    );
    state.goldenEggs += reward.goldenEggs;
    return reward;
  }

  /// Wiki Soul Egg formula: seven earnings bands with rising exponents.
  double get soulEggsGained {
    final earnings = state.cashEarnedThisPrestige;
    if (!earnings.isFinite || earnings <= 0) {
      return 0;
    }
    const exponents = [0.15, 0.16, 0.17, 0.18, 0.19, 0.20, 0.21];
    const bandStarts = [1.0, 1e12, 1e21, 1e30, 1e39, 1e48, 1e60];
    var total = 0.0;
    for (var band = 0; band < exponents.length; band++) {
      final bandEnd =
          band + 1 < bandStarts.length ? bandStarts[band + 1] : double.infinity;
      total += math.max(
        0.0,
        math.pow(1e-6 * math.min(earnings, bandEnd), exponents[band]) -
            math.pow(1e-6 * bandStarts[band], exponents[band]),
      );
    }
    return (epicResearchMultiplier('prestigeBonus') * total).floorToDouble();
  }

  /// Interpolates the configured epic-research price for the next level.
  double epicResearchCost(String researchId) {
    final item = _epicResearchItem(researchId);
    final level = epicResearchLevel(researchId);
    if (level >= item.maxLevel) {
      return double.infinity;
    }
    if (item.maxLevel == 1) {
      return item.lastCost * BalanceConfig.goldenEggCostScale;
    }
    final costSteps =
        ((level * (item.lastCost - item.firstCost)) / (item.maxLevel - 1))
            .floorToDouble();
    return (item.firstCost + costSteps) * BalanceConfig.goldenEggCostScale;
  }

  /// Buys one permanent epic-research level using Golden Eggs.
  bool buyEpicResearch(String researchId) {
    final item = _epicResearchItem(researchId);
    final cost = epicResearchCost(researchId);
    if (state.goldenEggs < cost || !cost.isFinite) {
      return false;
    }
    state.goldenEggs -= cost;
    _addPiggyBankGoldenEggs(BalanceConfig.piggyBankResearchReward);
    state.epicResearchLevels[item.id] = epicResearchLevel(item.id) + 1;
    return true;
  }

  /// Returns the fixed wiki chicken-count threshold for a trophy tier.
  double trophyChickenCountThreshold(int trophyIndex) {
    if (trophyIndex < 0 ||
        trophyIndex >= BalanceConfig.trophyChickenCountThresholds.length) {
      throw RangeError.range(
        trophyIndex,
        0,
        BalanceConfig.trophyChickenCountThresholds.length - 1,
        'trophyIndex',
      );
    }
    return BalanceConfig.trophyChickenCountThresholds[trophyIndex];
  }

  /// Awards page-listed trophy rewards once when their chicken thresholds hit.
  void _awardChickenCountTrophies() {
    final eggId = currentEgg.id;
    for (var index = 0;
        index < BalanceConfig.trophyChickenCountThresholds.length;
        index++) {
      final trophyId = '$eggId:trophy:$index';
      if (state.trophies.contains(trophyId) ||
          state.chickens < trophyChickenCountThreshold(index)) {
        continue;
      }
      final soulEggRewards = BalanceConfig.trophySoulEggRewards[eggId];
      final goldenEggRewards = BalanceConfig.trophyGoldenEggRewards[eggId];
      state.trophies.add(trophyId);
      if (soulEggRewards != null && index < soulEggRewards.length) {
        state.soulEggs += soulEggRewards[index];
      }
      if (goldenEggRewards != null && index < goldenEggRewards.length) {
        state.goldenEggs += goldenEggRewards[index];
      }
    }
  }

  double get siloMinutes =>
      BalanceConfig.siloBaseMinutes +
      BalanceConfig.siloEpicMinutesPerLevel *
          epicResearchLevel('silo_capacity');

  /// Wiki farm value formula (research only; boosts never count):
  /// 500 * L * A * EB * V * E * (Peff + space^0.6 + H) * (RCB - 4)^0.25.
  double get farmValue {
    final eggsPerChicken =
        BalanceConfig.baseEggsPerChickenPerMinute * layRateMultiplier;
    final population = state.chickens;
    final shippingLimit =
        (shipCapacityPerMinute / eggsPerChicken).floorToDouble();
    final effectivePopulation =
        (0.8 * math.min(population, shippingLimit) + 0.2 * population)
            .floorToDouble();
    final emptySpace = math.max(totalHabCapacity - population, 0.0);
    final awayHatching = flatResearchBonus('ihrPerHab') *
        epicResearchMultiplier('ihrMult') *
        state.siloCount *
        siloMinutes;
    return 500 *
        (eggIndex + 2) *
        (1 + epicResearchEffect('farmValueMult')) *
        earningsMultiplier *
        currentEgg.valuePerEgg *
        eggValueMultiplier *
        eggsPerChicken *
        (effectivePopulation + math.pow(emptySpace, 0.6) + awayHatching) *
        math.pow(maximumRunningChickenBonus - 4, 0.25);
  }

  /// Wiki silo price: 100,000 * (n - 1)^(n + 14) for the nth silo.
  double get nextSiloPrice {
    final next = state.siloCount + 1;
    if (next > BalanceConfig.maximumSiloCount) {
      return double.infinity;
    }
    return 100000 * math.pow(next - 1, next + 14).toDouble();
  }

  bool buySilo() => _spendCash(nextSiloPrice, () => state.siloCount++);

  double? get nextEggUpgradeFarmValue {
    if (eggIndex + 1 >= data.eggs.length) {
      return null;
    }
    final nextEgg = data.eggs[eggIndex + 1];
    return nextEgg.upgradeFarmValue;
  }

  bool get canAscend {
    final threshold = nextEggUpgradeFarmValue;
    return threshold != null && farmValue >= threshold;
  }

  bool get eggsBackingUp => eggsLaidPerMinute > shipCapacityPerMinute;

  BoostData _boostItem(String id) {
    for (final item in data.boosts) {
      if (item.id == id) {
        return item;
      }
    }
    throw ArgumentError.value(id, 'boostId', 'Unknown boost id.');
  }

  static List<double> _shiftDroneWeights(
    List<double> baseWeights,
    double requestedShift,
  ) {
    final shift = math.min(
      baseWeights.first,
      math.max(0.0, requestedShift),
    );
    final weights = List<double>.of(baseWeights);
    weights[0] -= shift;
    weights[weights.length - 1] += shift;
    return weights;
  }

  static int _weightedIndex(List<double> weights, double roll) {
    final totalWeight =
        weights.fold<double>(0, (total, weight) => total + weight);
    var threshold = roll * totalWeight;
    for (var index = 0; index < weights.length; index++) {
      threshold -= weights[index];
      if (threshold < 0) {
        return index;
      }
    }
    return weights.length - 1;
  }

  static void _validateDroneRoll(double value, String name) {
    if (!value.isFinite || value < 0 || value >= 1) {
      throw ArgumentError.value(value, name, 'Must be in [0, 1).');
    }
  }

  /// Applies common habitat and portal-capacity research, respecting wiki caps.
  double capacityForHab(int tierIndex) {
    _checkIndex(tierIndex, data.habs.length, 'hab tier');
    final hab = data.habs[tierIndex];
    final baseMultiplier = math.min(
      hab.maxCapacityMultiplier,
      math.min(
        BalanceConfig.maxBaseHabCapacityMultiplier,
        researchMultiplier('habCapacity'),
      ),
    );
    final portalMultiplier = tierIndex >= BalanceConfig.firstPortalHabTierIndex
        ? researchMultiplier('portalHabCapacity')
        : BalanceConfig.baseResearchMultiplier;
    return hab.baseCapacity *
        math.min(hab.maxCapacityMultiplier, baseMultiplier * portalMultiplier);
  }

  /// Returns the next base-habitat price from its slot price table.
  double habPrice(int tierIndex, {int? slotIndex}) {
    _checkIndex(tierIndex, data.habs.length, 'hab tier');
    final targetSlot = slotIndex ?? _nextFreeHabSlot();
    if (targetSlot < 0 ||
        targetSlot >= data.habs[tierIndex].slotPrices.length ||
        state.habs.length >= BalanceConfig.maximumHabCount ||
        state.habs.any((hab) => hab.slotIndex == targetSlot)) {
      return double.infinity;
    }
    return data.habs[tierIndex].slotPrices[targetSlot] * _habPriceMultiplier;
  }

  double habUpgradePrice(int tierIndex, int slotIndex) =>
      data.habs[tierIndex].slotPrices[slotIndex] * _habPriceMultiplier;

  double get _habPriceMultiplier => 1 - epicResearchEffect('habCostReduction');

  /// Interpolates the tunable normalized unit curves by vehicle tier.
  double vehiclePrice(int tierIndex, int unitNumber) {
    _checkIndex(tierIndex, data.vehicles.length, 'vehicle tier');
    if (unitNumber < 1) {
      throw RangeError.value(unitNumber, 'unitNumber', 'Must be at least one.');
    }
    final tierPosition = tierIndex / (data.vehicles.length - 1);
    final curveA = _vehicleCurveValue(
      BalanceConfig.vehiclePriceCurveA,
      unitNumber,
    );
    final curveB = _vehicleCurveValue(
      BalanceConfig.vehiclePriceCurveB,
      unitNumber,
    );
    final curve = curveA + (curveB - curveA) * tierPosition;
    return data.vehicles[tierIndex].firstPrice *
        curve *
        (1 - epicResearchEffect('vehicleCostReduction'));
  }

  /// Multiplies add/mul research factors that target the requested effect.
  double researchMultiplier(String effect) {
    var multiplier = BalanceConfig.baseResearchMultiplier;
    for (final item in data.commonResearch) {
      if (!_targetsEffect(item.effect, effect)) {
        continue;
      }
      final level = _researchLevel(item.id, item.maxLevel);
      if (level == 0) {
        continue;
      }
      switch (item.mode) {
        case 'add':
          multiplier *=
              BalanceConfig.baseResearchMultiplier + item.perLevel * level;
          break;
        case 'mul':
          multiplier *= math.pow(item.perLevel, level).toDouble();
          break;
      }
    }
    return multiplier;
  }

  /// Sums flat research effects such as fleet size and internal hatcheries.
  double flatResearchBonus(String effect) {
    var bonus = 0.0;
    for (final item in data.commonResearch) {
      if (item.mode == 'flat' && _targetsEffect(item.effect, effect)) {
        bonus += item.perLevel * _researchLevel(item.id, item.maxLevel);
      }
    }
    return bonus;
  }

  double epicResearchEffect(String effect) {
    var total = 0.0;
    for (final item in data.epicResearch) {
      if (item.effect == effect) {
        total += item.perLevel *
            (state.epicResearchLevels[item.id] ?? 0).clamp(0, item.maxLevel);
      }
    }
    return total;
  }

  int epicResearchLevel(String id) {
    final item = data.epicResearch.where((item) => item.id == id).firstOrNull;
    if (item == null) {
      throw ArgumentError.value(id, 'researchId', 'Unknown epic research id.');
    }
    return (state.epicResearchLevels[id] ?? 0).clamp(0, item.maxLevel);
  }

  double epicResearchMultiplier(String effect) =>
      BalanceConfig.baseResearchMultiplier + epicResearchEffect(effect);

  /// Reads the wiki per-level price, less the Lab Upgrade epic discount.
  double commonResearchCost(String researchId) {
    final item = _commonResearchItem(researchId);
    final level = _researchLevel(item.id, item.maxLevel);
    if (level >= item.maxLevel) {
      return double.infinity;
    }
    return item.costs[level] *
        (1 - epicResearchEffect('researchCostReduction'));
  }

  /// Unlocks a tier when bought research levels in all lower tiers meet its
  /// threshold from common_research.json.
  bool isCommonResearchTierUnlocked(int tier) {
    if (tier < BalanceConfig.firstResearchTier) {
      return false;
    }
    if (tier == BalanceConfig.firstResearchTier) {
      return true;
    }
    final thresholdIndex = tier - 1;
    if (thresholdIndex >= data.commonResearchTierUnlocks.length) {
      return false;
    }
    final previousTierLevels = data.commonResearch
        .where((item) => item.tier != null && item.tier! < tier)
        .fold<int>(
          0,
          (total, item) => total + _researchLevel(item.id, item.maxLevel),
        );
    return previousTierLevels >= data.commonResearchTierUnlocks[thresholdIndex];
  }

  /// Buys the next level of an unlocked common research item for farm cash.
  bool buyCommonResearch(String researchId) {
    final item = _commonResearchItem(researchId);
    if (!isCommonResearchTierUnlocked(item.tier!)) {
      return false;
    }
    final cost = commonResearchCost(researchId);
    if (state.cash < cost) {
      return false;
    }
    state.cash -= cost;
    state.cashSpentThisRun += cost;
    state.commonResearchLevels[item.id] =
        _researchLevel(item.id, item.maxLevel) + 1;
    _addPiggyBankGoldenEggs(BalanceConfig.piggyBankResearchReward);
    return true;
  }

  /// Prestiges to Edible, awarding Soul Eggs and keeping permanent progress.
  double prestige() {
    final gainedSoulEggs = soulEggsGained;
    state.soulEggs += gainedSoulEggs;
    state.eggIndex = 0;
    state.cash = 0;
    state.cashEarnedThisPrestige = 0;
    state.cashEarnedThisRun = 0;
    state.cashSpentThisRun = 0;
    state.chickens = 0;
    state.hatcheryStock = BalanceConfig.baseHatcheryCapacity;
    state.habs
      ..clear()
      ..add(const HabOwnership(0, 0));
    state.vehicles
      ..clear()
      ..add(const VehicleOwnership(0, 1, 0));
    state.commonResearchLevels.clear();
    state.siloCount = BalanceConfig.initialSiloCount;
    state.runningChickenBatches.clear();
    return gainedSoulEggs;
  }

  /// Ticks cash and chicken production using the spec's per-second formulas.
  void tick(
    double elapsedSeconds, {
    bool refillHatchery = true,
    double manualHatchPerSecond = 0,
  }) {
    if (!elapsedSeconds.isFinite || elapsedSeconds <= 0) {
      throw ArgumentError.value(
        elapsedSeconds,
        'elapsedSeconds',
        'Must be finite and greater than zero.',
      );
    }

    if (!manualHatchPerSecond.isFinite || manualHatchPerSecond < 0) {
      throw ArgumentError.value(
        manualHatchPerSecond,
        'manualHatchPerSecond',
        'Must be finite and non-negative.',
      );
    }

    var remainingSeconds = elapsedSeconds;
    while (remainingSeconds > 0) {
      final step = math.min(
        remainingSeconds,
        math.min(
          _secondsUntilBoostExpiry(),
          _secondsUntilRunningBatchExpiry(),
        ),
      );
      _tickInterval(
        step,
        refillHatchery: refillHatchery,
        manualHatchPerSecond: manualHatchPerSecond,
      );
      remainingSeconds -= step;
    }
  }

  void _tickInterval(
    double elapsedSeconds, {
    required bool refillHatchery,
    required double manualHatchPerSecond,
  }) {
    final ihrPerSecond = _internalHatcheryGrowthPerSecond();
    var remainingSeconds = elapsedSeconds;
    var cashEarned = 0.0;
    if (manualHatchPerSecond > 0 && state.hatcheryStock > 0) {
      final room = math.max(0.0, totalHabCapacity - state.chickens).toDouble();
      final holdingSeconds = math
          .min(
            elapsedSeconds,
            math.min(
              state.hatcheryStock / manualHatchPerSecond,
              room / (manualHatchPerSecond + ihrPerSecond),
            ),
          )
          .toDouble();
      if (holdingSeconds > 0) {
        cashEarned += _cashEarnedWithRunningBonus(
          holdingSeconds,
          startingChickens: state.chickens,
          growthPerSecond: manualHatchPerSecond + ihrPerSecond,
        );
        state.chickens = _chickensAfterGrowth(
          holdingSeconds,
          manualHatchPerSecond + ihrPerSecond,
        );
        state.hatcheryStock = math.max(
          0.0,
          state.hatcheryStock - manualHatchPerSecond * holdingSeconds,
        );
        remainingSeconds -= holdingSeconds;
      }
    }
    if (remainingSeconds > 0) {
      cashEarned += _cashEarnedWithRunningBonus(
        remainingSeconds,
        startingChickens: state.chickens,
        growthPerSecond: ihrPerSecond,
      );
      state.chickens = _chickensAfterGrowth(remainingSeconds, ihrPerSecond);
    }
    _creditCash(cashEarned);

    if (refillHatchery) {
      _refillHatchery(
          manualHatchPerSecond == 0 ? elapsedSeconds : remainingSeconds);
    }
    _awardChickenCountTrophies();
    _advanceBoostTimers(elapsedSeconds);
    _advanceRunningChickenBatches(elapsedSeconds);
  }

  /// Simulates capped offline production in configured chunks and integrates
  /// chicken growth, shipping, earnings, and stock refill in each chunk.
  OfflineProgress simulateOffline(double requestedSeconds) {
    if (!requestedSeconds.isFinite || requestedSeconds < 0) {
      throw ArgumentError.value(
        requestedSeconds,
        'requestedSeconds',
        'Must be finite and non-negative.',
      );
    }
    final maximumAwaySeconds =
        state.siloCount * siloMinutes * BalanceConfig.secondsPerMinute;
    var remainingSeconds =
        math.min(requestedSeconds, maximumAwaySeconds).toDouble();
    var elapsedSeconds = 0.0;
    final initialCash = state.cash;
    final initialChickens = state.chickens;
    final initialHatcheryStock = state.hatcheryStock;

    final chunkSeconds = BalanceConfig.offlineProgressChunkSeconds.toDouble();
    var steps = 0;
    while (remainingSeconds > 0 &&
        steps < BalanceConfig.offlineProgressMaxChunkSteps) {
      final step = math
          .min(
            math.min(remainingSeconds, chunkSeconds),
            math.min(
              _secondsUntilBoostExpiry(),
              _secondsUntilRunningBatchExpiry(),
            ),
          )
          .toDouble();
      _simulateOfflineStep(step);
      remainingSeconds -= step;
      elapsedSeconds += step;
      steps++;
    }

    while (remainingSeconds > 0) {
      final step = math
          .min(
            remainingSeconds,
            math.min(
              _secondsUntilBoostExpiry(),
              _secondsUntilRunningBatchExpiry(),
            ),
          )
          .toDouble();
      _simulateOfflineStep(step);
      remainingSeconds -= step;
      elapsedSeconds += step;
    }

    return OfflineProgress(
      elapsedSeconds: elapsedSeconds,
      cashEarned: state.cash - initialCash,
      chickensAdded: state.chickens - initialChickens,
      hatcheryStockAdded: state.hatcheryStock - initialHatcheryStock,
    );
  }

  /// Hatches available stock, limited by total capacity (base hatch size per spec).
  double hatch({double requested = 1}) {
    if (!requested.isFinite || requested <= 0) {
      throw ArgumentError.value(
        requested,
        'requested',
        'Must be finite and greater than zero.',
      );
    }
    final room = math.max(0.0, totalHabCapacity - state.chickens).toDouble();
    final count =
        math.min(requested, math.min(state.hatcheryStock, room)).toDouble();
    state.hatcheryStock -= count;
    state.chickens += count;
    if (count > 0) {
      state.runningChickenBatches.add(
        RunningChickenBatch(
          chickens: count,
          secondsRemaining: BalanceConfig.runningChickenDurationSeconds,
        ),
      );
    }
    _awardChickenCountTrophies();
    return count;
  }

  double holdHatch(double elapsedSeconds, {required double accumulated}) {
    if (!elapsedSeconds.isFinite || elapsedSeconds < 0) {
      throw ArgumentError.value(
        elapsedSeconds,
        'elapsedSeconds',
        'Must be finite and non-negative.',
      );
    }
    if (!accumulated.isFinite || accumulated < 0 || accumulated >= 1) {
      throw ArgumentError.value(
        accumulated,
        'accumulated',
        'Must be a fractional chicken amount in [0, 1).',
      );
    }
    final availableRoom = totalHabCapacity - state.chickens;
    if (state.hatcheryStock <= 0 || availableRoom <= 0) {
      return 0;
    }

    final accumulatedChickens = accumulated +
        holdHatchPerSecond * elapsedSeconds +
        BalanceConfig.fractionalChickenEpsilon;
    final wholeChickenCount = accumulatedChickens.floorToDouble();
    if (wholeChickenCount <= 0) {
      return 0;
    }
    return hatch(
      requested: math
          .min(
            wholeChickenCount,
            math.min(state.hatcheryStock, availableRoom),
          )
          .toDouble(),
    );
  }

  bool buyHab(int tierIndex, {int? slotIndex}) {
    _checkIndex(tierIndex, data.habs.length, 'hab tier');
    if (state.habs.length >= BalanceConfig.maximumHabCount) {
      return false;
    }
    final targetSlot = slotIndex ?? _nextFreeHabSlot();
    final price = habPrice(tierIndex, slotIndex: targetSlot);
    if (!price.isFinite) {
      return false;
    }
    return _spendCash(
      price,
      () => state.habs.add(HabOwnership(tierIndex, targetSlot)),
      piggyBankReward: BalanceConfig.piggyBankHabReward,
    );
  }

  /// Sells the farm for the next egg and starts a fresh run without prestige.
  bool ascend() {
    if (!canAscend || eggIndex + 1 >= data.eggs.length) {
      return false;
    }
    state.eggIndex++;
    state.cash = 0;
    state.cashEarnedThisRun = 0;
    state.cashSpentThisRun = 0;
    state.chickens = 0;
    state.hatcheryStock = BalanceConfig.baseHatcheryCapacity;
    state.habs
      ..clear()
      ..add(const HabOwnership(0, 0));
    state.vehicles
      ..clear()
      ..add(const VehicleOwnership(0, 1, 0));
    state.commonResearchLevels.clear();
    state.siloCount = BalanceConfig.initialSiloCount;
    state.runningChickenBatches.clear();
    return true;
  }

  bool upgradeHab(
    int tierIndex,
    int slotIndex, {
    int? targetTierIndex,
  }) {
    _checkIndex(tierIndex, data.habs.length, 'hab tier');
    if (slotIndex < 0 || slotIndex >= BalanceConfig.maximumHabCount) {
      throw RangeError.value(slotIndex, 'slotIndex');
    }
    final ownedIndex = state.habs.indexWhere(
      (hab) => hab.tierIndex == tierIndex && hab.slotIndex == slotIndex,
    );
    final nextTier = targetTierIndex ?? tierIndex + 1;
    if (ownedIndex < 0 ||
        nextTier <= tierIndex ||
        nextTier >= data.habs.length) {
      return false;
    }

    final price = habUpgradePrice(nextTier, slotIndex);
    return _spendCash(
      price,
      () => state.habs[ownedIndex] = HabOwnership(nextTier, slotIndex),
      piggyBankReward: BalanceConfig.piggyBankHabReward,
    );
  }

  bool buyVehicle(int tierIndex, {int? slotIndex}) {
    _checkIndex(tierIndex, data.vehicles.length, 'vehicle tier');
    if (state.vehicles.length >= maximumFleetSize ||
        state.vehicles.length >= BalanceConfig.maximumFleetSlotCount) {
      return false;
    }
    final targetSlot = slotIndex ?? _nextFreeVehicleSlot();
    if (targetSlot < 0 ||
        targetSlot >= maximumFleetSize ||
        state.vehicles.any((vehicle) => vehicle.slotIndex == targetSlot)) {
      return false;
    }
    if (data.vehicles[tierIndex].firstPrice == 0 &&
        state.vehicles.any((vehicle) => vehicle.tierIndex == tierIndex)) {
      return false;
    }
    final unitNumber = state.vehicles
            .where((vehicle) => vehicle.tierIndex == tierIndex)
            .length +
        1;
    final price = vehiclePrice(tierIndex, unitNumber);
    return _spendCash(
      price,
      () => state.vehicles.add(
        VehicleOwnership(tierIndex, unitNumber, targetSlot),
      ),
      piggyBankReward: BalanceConfig.piggyBankVehicleReward,
    );
  }

  double vehicleUpgradePrice(int targetTierIndex) {
    _checkIndex(targetTierIndex, data.vehicles.length, 'vehicle tier');
    final unitNumber = state.vehicles
            .where((vehicle) => vehicle.tierIndex == targetTierIndex)
            .length +
        1;
    return vehiclePrice(targetTierIndex, unitNumber);
  }

  bool upgradeVehicle(
    int slotIndex, {
    required int targetTierIndex,
  }) {
    if (slotIndex < 0 || slotIndex >= maximumFleetSize) {
      throw RangeError.value(slotIndex, 'slotIndex');
    }
    final ownedIndex =
        state.vehicles.indexWhere((vehicle) => vehicle.slotIndex == slotIndex);
    if (ownedIndex < 0) {
      return false;
    }
    final currentVehicle = state.vehicles[ownedIndex];
    _checkIndex(targetTierIndex, data.vehicles.length, 'vehicle tier');
    if (targetTierIndex <= currentVehicle.tierIndex) {
      return false;
    }
    final targetCount = state.vehicles
            .where((vehicle) => vehicle.tierIndex == targetTierIndex)
            .length +
        1;
    final price = vehiclePrice(targetTierIndex, targetCount);
    return _spendCash(
      price,
      () => state.vehicles[ownedIndex] = VehicleOwnership(
        targetTierIndex,
        targetCount,
        slotIndex,
      ),
      piggyBankReward: BalanceConfig.piggyBankVehicleReward,
    );
  }

  /// Soul Beacons multiply the earnings fed into the Soul Egg formula (wiki).
  void _creditCash(double amount) {
    state.cash += amount;
    state.cashEarnedThisPrestige += amount * activeSoulBeaconMultiplier;
    state.cashEarnedThisRun += amount;
  }

  bool _spendCash(
    double price,
    void Function() purchase, {
    double piggyBankReward = 0,
  }) {
    if (state.cash < price) {
      return false;
    }
    state.cash -= price;
    state.cashSpentThisRun += price;
    purchase();
    _addPiggyBankGoldenEggs(piggyBankReward);
    return true;
  }

  void _addPiggyBankGoldenEggs(double amount) {
    if (BalanceConfig.piggyBankEnabled) {
      state.piggyBankGoldenEggs += amount;
    }
  }

  bool crackPiggyBank() {
    if (!BalanceConfig.piggyBankEnabled || state.piggyBankGoldenEggs <= 0) {
      return false;
    }
    state.goldenEggs += state.piggyBankGoldenEggs;
    state.piggyBankGoldenEggs = 0;
    return true;
  }

  void _simulateOfflineStep(double elapsedSeconds) {
    final growthRate = _internalHatcheryGrowthPerSecond() *
        epicResearchMultiplier('ihrAwayMult');
    final cashEarned = BalanceConfig.offlineEarningsFraction *
        _cashEarnedDuring(
          elapsedSeconds,
          startingChickens: state.chickens,
          growthPerSecond: growthRate,
        );
    _creditCash(cashEarned);
    state.chickens = _chickensAfterGrowth(elapsedSeconds, growthRate);
    _refillHatchery(elapsedSeconds);
    _awardChickenCountTrophies();
    _advanceBoostTimers(elapsedSeconds);
    _advanceRunningChickenBatches(elapsedSeconds);
  }

  void _refillHatchery(double elapsedSeconds) {
    final refill = hatcheryRefillPerMinute *
        elapsedSeconds /
        BalanceConfig.secondsPerMinute;
    state.hatcheryStock =
        math.min(hatcheryCapacity, state.hatcheryStock + refill);
  }

  double _internalHatcheryGrowthPerSecond() =>
      flatResearchBonus('ihrPerHab') *
      habCount *
      epicResearchMultiplier('ihrMult') /
      BalanceConfig.secondsPerMinute *
      activeBoostMultiplier('internalHatchery');

  double _secondsUntilBoostExpiry() {
    final activeTimers =
        state.activeBoostSeconds.values.where((seconds) => seconds > 0);
    if (activeTimers.isEmpty) {
      return double.infinity;
    }
    return activeTimers.reduce(
      (first, second) => first < second ? first : second,
    );
  }

  void _advanceBoostTimers(double elapsedSeconds) {
    for (final id in state.activeBoostSeconds.keys.toList(growable: false)) {
      final remaining = state.activeBoostSeconds[id]! - elapsedSeconds;
      if (remaining <= 0) {
        state.activeBoostSeconds.remove(id);
        state.activeBoostMultipliers.remove(id);
      } else {
        state.activeBoostSeconds[id] = remaining;
      }
    }
  }

  double _secondsUntilRunningBatchExpiry() {
    if (state.runningChickenBatches.isEmpty) {
      return double.infinity;
    }
    return state.runningChickenBatches
        .map((batch) => batch.secondsRemaining)
        .reduce((first, second) => first < second ? first : second);
  }

  void _advanceRunningChickenBatches(double elapsedSeconds) {
    final batches = state.runningChickenBatches
        .map((batch) => batch.elapse(elapsedSeconds))
        .where((batch) => batch.secondsRemaining > 0)
        .toList();
    state.runningChickenBatches
      ..clear()
      ..addAll(batches);
  }

  double _chickensAfterGrowth(double elapsedSeconds, double growthPerSecond) =>
      math
          .min(
            totalHabCapacity,
            state.chickens + growthPerSecond * elapsedSeconds,
          )
          .toDouble();

  double _cashEarnedDuring(
    double elapsedSeconds, {
    required double startingChickens,
    required double growthPerSecond,
    double runningMultiplier = 1,
  }) {
    if (elapsedSeconds <= 0 || state.vehicles.isEmpty) {
      return 0;
    }

    final eggsLaidPerMinutePerChicken =
        BalanceConfig.baseEggsPerChickenPerMinute * layRateMultiplier;
    final cashPerEgg = currentEgg.valuePerEgg *
        eggValueMultiplier *
        earningsMultiplier *
        runningMultiplier *
        activeBoostMultiplier('earnings');
    final cashFromLayingPerChickenSecond = eggsLaidPerMinutePerChicken /
        BalanceConfig.secondsPerMinute *
        cashPerEgg;
    final cashFromShippingPerSecond =
        shipCapacityPerMinute / BalanceConfig.secondsPerMinute * cashPerEgg;
    if (cashFromLayingPerChickenSecond <= 0 || cashFromShippingPerSecond <= 0) {
      return 0;
    }

    final shippingChickenLimit =
        cashFromShippingPerSecond / cashFromLayingPerChickenSecond;
    final durationUntilHabFull = growthPerSecond <= 0
        ? double.infinity
        : (totalHabCapacity - startingChickens) / growthPerSecond;
    final durationUntilShippingLimit = growthPerSecond <= 0
        ? double.infinity
        : (shippingChickenLimit - startingChickens) / growthPerSecond;
    final breakpoints = <double>[
      0,
      elapsedSeconds,
      if (durationUntilHabFull > 0 && durationUntilHabFull < elapsedSeconds)
        durationUntilHabFull,
      if (durationUntilShippingLimit > 0 &&
          durationUntilShippingLimit < elapsedSeconds)
        durationUntilShippingLimit,
    ]..sort();

    var earnings = 0.0;
    for (var index = 0; index + 1 < breakpoints.length; index++) {
      final from = breakpoints[index];
      final until = breakpoints[index + 1];
      final duration = until - from;
      if (duration <= 0) {
        continue;
      }
      final midpoint = (from + until) / 2;
      final chickensAtMidpoint = math.min(
        totalHabCapacity,
        startingChickens + growthPerSecond * midpoint,
      );
      if (chickensAtMidpoint >= shippingChickenLimit) {
        earnings += cashFromShippingPerSecond * duration;
      } else if (chickensAtMidpoint >= totalHabCapacity) {
        earnings +=
            cashFromLayingPerChickenSecond * totalHabCapacity * duration;
      } else {
        earnings += cashFromLayingPerChickenSecond *
            (startingChickens * duration +
                growthPerSecond * (until * until - from * from) / 2);
      }
    }
    return earnings;
  }

  double _cashEarnedWithRunningBonus(
    double elapsedSeconds, {
    required double startingChickens,
    required double growthPerSecond,
  }) {
    final runningMultiplier = runningChickenMultiplier;
    final secondsUntilHabFull = growthPerSecond <= 0
        ? double.infinity
        : math.max(0.0, totalHabCapacity - startingChickens) / growthPerSecond;
    final bonusDuration =
        math.min(elapsedSeconds, secondsUntilHabFull).toDouble();
    var earnings = _cashEarnedDuring(
      bonusDuration,
      startingChickens: startingChickens,
      growthPerSecond: growthPerSecond,
      runningMultiplier: runningMultiplier,
    );
    if (bonusDuration < elapsedSeconds) {
      final chickensAtBonusEnd = _chickensAfterGrowth(
        bonusDuration,
        growthPerSecond,
      );
      earnings += _cashEarnedDuring(
        elapsedSeconds - bonusDuration,
        startingChickens: chickensAtBonusEnd,
        growthPerSecond: growthPerSecond,
      );
    }
    return earnings;
  }

  int _researchLevel(String id, int maxLevel) {
    final level = state.commonResearchLevels[id] ?? 0;
    return level.clamp(0, maxLevel);
  }

  ResearchData _commonResearchItem(String id) {
    for (final item in data.commonResearch) {
      if (item.id == id) {
        return item;
      }
    }
    throw ArgumentError.value(id, 'researchId', 'Unknown common research id.');
  }

  ResearchData _epicResearchItem(String id) {
    for (final item in data.epicResearch) {
      if (item.id == id) {
        return item;
      }
    }
    throw ArgumentError.value(id, 'researchId', 'Unknown epic research id.');
  }

  int _nextFreeHabSlot() {
    for (var slotIndex = 0;
        slotIndex < BalanceConfig.maximumHabCount;
        slotIndex++) {
      final isOccupied = state.habs.any(
        (hab) => hab.slotIndex == slotIndex,
      );
      if (!isOccupied) {
        return slotIndex;
      }
    }
    return -1;
  }

  int _nextFreeVehicleSlot() {
    final maximumSlots = maximumFleetSize.floor();
    for (var slotIndex = 0; slotIndex < maximumSlots; slotIndex++) {
      if (!state.vehicles.any((vehicle) => vehicle.slotIndex == slotIndex)) {
        return slotIndex;
      }
    }
    return -1;
  }

  static double _vehicleCurveValue(List<double> curve, int unitNumber) {
    if (unitNumber <= curve.length) {
      return curve[unitNumber - 1];
    }
    var value = curve.last;
    for (var unit = curve.length; unit < unitNumber; unit++) {
      value *= BalanceConfig.vehiclePriceExtrapolationMultiplier;
    }
    return value;
  }

  static bool _targetsEffect(String itemEffect, String effect) =>
      itemEffect == effect ||
      itemEffect.startsWith('$effect+') ||
      itemEffect.endsWith('+$effect') ||
      itemEffect.contains('+$effect+');

  static void _checkIndex(int index, int length, String name) {
    if (index < 0 || index >= length) {
      throw RangeError.range(index, 0, length - 1, name);
    }
  }
}

class GameState {
  GameState({
    required this.habs,
    required this.vehicles,
    required this.hatcheryStock,
    this.cash = 0,
    this.cashEarnedThisPrestige = 0,
    this.cashEarnedThisRun = 0,
    this.cashSpentThisRun = 0,
    this.chickens = 0,
    this.eggIndex = 0,
    Map<String, int>? commonResearchLevels,
    Map<String, int>? epicResearchLevels,
    this.goldenEggs = 0,
    this.piggyBankGoldenEggs = 0,
    this.soulEggs = 0,
    this.siloCount = BalanceConfig.initialSiloCount,
    this.hapticsEnabled = BalanceConfig.hapticFeedbackDefaultEnabled,
    Map<String, double>? activeBoostSeconds,
    Map<String, double>? activeBoostMultipliers,
    Set<String>? trophies,
    List<RunningChickenBatch>? runningChickenBatches,
    GardenState? garden,
  })  : commonResearchLevels = commonResearchLevels ?? {},
        epicResearchLevels = epicResearchLevels ?? {},
        activeBoostSeconds = activeBoostSeconds ?? {},
        activeBoostMultipliers = activeBoostMultipliers ?? {},
        trophies = trophies ?? {},
        runningChickenBatches = runningChickenBatches ?? [],
        garden = garden ?? GardenState();

  factory GameState.newGame() => GameState(
        habs: [const HabOwnership(0, 0)],
        vehicles: [const VehicleOwnership(0, 1, 0)],
        hatcheryStock: BalanceConfig.baseHatcheryCapacity,
      );

  double cash;
  double cashEarnedThisPrestige;
  double cashEarnedThisRun;
  double cashSpentThisRun;
  double chickens;
  double hatcheryStock;
  double goldenEggs;
  double piggyBankGoldenEggs;
  double soulEggs;
  int eggIndex;
  int siloCount;
  bool hapticsEnabled;
  final List<HabOwnership> habs;
  final List<VehicleOwnership> vehicles;
  final Map<String, int> commonResearchLevels;
  final Map<String, int> epicResearchLevels;
  final Map<String, double> activeBoostSeconds;
  final Map<String, double> activeBoostMultipliers;
  final Set<String> trophies;
  final List<RunningChickenBatch> runningChickenBatches;
  final GardenState garden;

  void resetToNewGame() {
    final fresh = GameState.newGame();
    cash = fresh.cash;
    cashEarnedThisPrestige = fresh.cashEarnedThisPrestige;
    cashEarnedThisRun = fresh.cashEarnedThisRun;
    cashSpentThisRun = fresh.cashSpentThisRun;
    chickens = fresh.chickens;
    hatcheryStock = fresh.hatcheryStock;
    goldenEggs = fresh.goldenEggs;
    piggyBankGoldenEggs = fresh.piggyBankGoldenEggs;
    soulEggs = fresh.soulEggs;
    eggIndex = fresh.eggIndex;
    siloCount = fresh.siloCount;
    hapticsEnabled = fresh.hapticsEnabled;
    habs
      ..clear()
      ..addAll(fresh.habs);
    vehicles
      ..clear()
      ..addAll(fresh.vehicles);
    commonResearchLevels.clear();
    epicResearchLevels.clear();
    activeBoostSeconds.clear();
    activeBoostMultipliers.clear();
    trophies.clear();
    runningChickenBatches.clear();
    garden.reset();
  }

  factory GameState.fromJson(Map<String, Object?> json, GameData data) {
    final savedHabs = _readObjectList(json, 'habs');
    if (savedHabs.isEmpty || savedHabs.length > BalanceConfig.maximumHabCount) {
      throw const FormatException(
        'Saved game must contain between one and four habitats.',
      );
    }
    final usedHabSlots = <int>{};
    final habs = savedHabs.map((item) {
      final tierIndex = _readInt(item, 'tierIndex');
      var slotIndex = _readInt(item, 'slotIndex');
      if (tierIndex < 0 || tierIndex >= data.habs.length) {
        throw FormatException('Invalid saved habitat tier $tierIndex.');
      }
      if (slotIndex < 0 || slotIndex >= BalanceConfig.maximumHabCount) {
        throw FormatException('Invalid saved habitat slot $slotIndex.');
      }
      if (!usedHabSlots.add(slotIndex)) {
        slotIndex = List<int>.generate(
          BalanceConfig.maximumHabCount,
          (index) => index,
        ).firstWhere((candidate) => !usedHabSlots.contains(candidate));
        usedHabSlots.add(slotIndex);
      }
      return HabOwnership(tierIndex, slotIndex);
    }).toList();
    final savedVehicles = _readObjectList(json, 'vehicles');
    if (savedVehicles.isEmpty ||
        savedVehicles.length > BalanceConfig.maximumFleetSlotCount) {
      throw const FormatException('Saved vehicle count is invalid.');
    }
    final usedVehicleSlots = <int>{};
    final vehicles = savedVehicles.map((item) {
      final tierIndex = _readInt(item, 'tierIndex');
      final unitNumber = _readInt(item, 'unitNumber');
      var slotIndex = item.containsKey('slotIndex')
          ? _readInt(item, 'slotIndex')
          : usedVehicleSlots.length;
      if (tierIndex < 0 ||
          tierIndex >= data.vehicles.length ||
          unitNumber < 1 ||
          slotIndex < 0 ||
          slotIndex >= BalanceConfig.maximumFleetSlotCount) {
        throw FormatException('Invalid saved vehicle entry.');
      }
      if (!usedVehicleSlots.add(slotIndex)) {
        slotIndex = List<int>.generate(
          BalanceConfig.maximumFleetSlotCount,
          (index) => index,
        ).firstWhere((candidate) => !usedVehicleSlots.contains(candidate));
        usedVehicleSlots.add(slotIndex);
      }
      return VehicleOwnership(tierIndex, unitNumber, slotIndex);
    }).toList();
    final eggIndex = _readInt(json, 'eggIndex');
    if (eggIndex < 0 || eggIndex >= data.eggs.length) {
      throw FormatException('Invalid saved egg index $eggIndex.');
    }
    if (vehicles.isEmpty) {
      throw const FormatException('Saved state needs at least one vehicle.');
    }
    return GameState(
      cash: _readDouble(json, 'cash'),
      cashEarnedThisPrestige: _readDouble(json, 'cashEarnedThisPrestige'),
      cashEarnedThisRun: _readDouble(json, 'cashEarnedThisRun'),
      cashSpentThisRun: _readDouble(json, 'cashSpentThisRun'),
      chickens: _readDouble(json, 'chickens'),
      hatcheryStock: _readDouble(json, 'hatcheryStock'),
      goldenEggs: _readDouble(json, 'goldenEggs'),
      piggyBankGoldenEggs: _optionalDouble(json, 'piggyBankGoldenEggs'),
      soulEggs: _readDouble(json, 'soulEggs'),
      eggIndex: eggIndex,
      siloCount: _readInt(json, 'siloCount'),
      hapticsEnabled: _readBool(json, 'hapticsEnabled'),
      habs: habs,
      vehicles: vehicles,
      commonResearchLevels: _readIntMap(json, 'commonResearchLevels'),
      epicResearchLevels: _readIntMap(json, 'epicResearchLevels'),
      activeBoostSeconds: _readDoubleMap(json, 'activeBoostSeconds'),
      activeBoostMultipliers:
          _optionalDoubleMap(json, 'activeBoostMultipliers'),
      trophies: _readStringSet(json, 'trophies'),
      runningChickenBatches: _optionalRunningChickenBatches(json),
      garden: GardenState.fromJson(json['garden'], data),
    );
  }

  Map<String, Object?> toJson() => {
        'cash': cash,
        'cashEarnedThisPrestige': cashEarnedThisPrestige,
        'cashEarnedThisRun': cashEarnedThisRun,
        'cashSpentThisRun': cashSpentThisRun,
        'chickens': chickens,
        'hatcheryStock': hatcheryStock,
        'goldenEggs': goldenEggs,
        'piggyBankGoldenEggs': piggyBankGoldenEggs,
        'soulEggs': soulEggs,
        'eggIndex': eggIndex,
        'siloCount': siloCount,
        'hapticsEnabled': hapticsEnabled,
        'habs': habs
            .map((hab) => {
                  'tierIndex': hab.tierIndex,
                  'slotIndex': hab.slotIndex,
                })
            .toList(),
        'vehicles': vehicles
            .map((vehicle) => {
                  'tierIndex': vehicle.tierIndex,
                  'unitNumber': vehicle.unitNumber,
                  'slotIndex': vehicle.slotIndex,
                })
            .toList(),
        'commonResearchLevels': commonResearchLevels,
        'epicResearchLevels': epicResearchLevels,
        'activeBoostSeconds': activeBoostSeconds,
        'activeBoostMultipliers': activeBoostMultipliers,
        'trophies': trophies.toList(),
        'garden': garden.toJson(),
        'runningChickenBatches': runningChickenBatches
            .map((batch) => {
                  'chickens': batch.chickens,
                  'secondsRemaining': batch.secondsRemaining,
                })
            .toList(),
      };
}

class HabOwnership {
  const HabOwnership(this.tierIndex, this.slotIndex);

  final int tierIndex;
  final int slotIndex;
}

class VehicleOwnership {
  const VehicleOwnership(this.tierIndex, this.unitNumber, [this.slotIndex = 0]);

  final int tierIndex;
  final int unitNumber;
  final int slotIndex;
}

class GameTicker {
  GameTicker(
    this.engine, {
    double ticksPerSecond = BalanceConfig.gameTicksPerSecond,
  }) : _tickIntervalSeconds = _validatedTickInterval(ticksPerSecond);

  final GameEngine engine;
  final double _tickIntervalSeconds;
  double _accumulatedSeconds = 0;

  /// Advances the engine in fixed updates while retaining any partial tick.
  int advance(double realDeltaSeconds, {bool refillHatchery = true}) {
    if (!realDeltaSeconds.isFinite || realDeltaSeconds < 0) {
      throw ArgumentError.value(
        realDeltaSeconds,
        'realDeltaSeconds',
        'Must be finite and non-negative.',
      );
    }
    _accumulatedSeconds += realDeltaSeconds;
    var tickCount = 0;
    while (_accumulatedSeconds >= _tickIntervalSeconds) {
      engine.tick(
        _tickIntervalSeconds,
        refillHatchery: refillHatchery,
      );
      _accumulatedSeconds -= _tickIntervalSeconds;
      tickCount++;
    }
    return tickCount;
  }

  static double _validatedTickInterval(double ticksPerSecond) {
    if (!ticksPerSecond.isFinite || ticksPerSecond <= 0) {
      throw ArgumentError.value(
        ticksPerSecond,
        'ticksPerSecond',
        'Must be finite and greater than zero.',
      );
    }
    return 1 / ticksPerSecond;
  }
}

class OfflineProgress {
  const OfflineProgress({
    required this.elapsedSeconds,
    required this.cashEarned,
    required this.chickensAdded,
    required this.hatcheryStockAdded,
  });

  final double elapsedSeconds;
  final double cashEarned;
  final double chickensAdded;
  final double hatcheryStockAdded;
}

List<Map<String, Object?>> _readObjectList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('Expected saved "$key" to be an array.');
  }
  return value.map((entry) {
    if (entry is! Map<String, Object?>) {
      throw FormatException('Expected saved "$key" entries to be objects.');
    }
    return entry;
  }).toList();
}

double _readDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.toDouble().isFinite || value < 0) {
    throw FormatException(
      'Expected saved "$key" to be a finite non-negative number.',
    );
  }
  return value.toDouble();
}

double _optionalDouble(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    return 0;
  }
  return _readDouble(json, key);
}

List<RunningChickenBatch> _optionalRunningChickenBatches(
  Map<String, Object?> json,
) {
  if (!json.containsKey('runningChickenBatches')) {
    return [];
  }
  return _readObjectList(json, 'runningChickenBatches')
      .map(
        (batch) => RunningChickenBatch(
          chickens: _readDouble(batch, 'chickens'),
          secondsRemaining: _readDouble(batch, 'secondsRemaining'),
        ),
      )
      .where((batch) => batch.chickens > 0 && batch.secondsRemaining > 0)
      .toList();
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException(
      'Expected saved "$key" to be a non-negative integer.',
    );
  }
  return value;
}

bool _readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('Expected saved "$key" to be a boolean.');
  }
  return value;
}

Map<String, int> _readIntMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected saved "$key" to be an object.');
  }
  return value.map((name, level) {
    if (level is! int || level < 0) {
      throw FormatException('Expected saved "$key" values to be non-negative.');
    }
    return MapEntry(name, level);
  });
}

Map<String, double> _readDoubleMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected saved "$key" to be an object.');
  }
  return value.map((name, seconds) {
    if (seconds is! num || !seconds.toDouble().isFinite || seconds < 0) {
      throw FormatException(
        'Expected saved "$key" values to be finite and non-negative.',
      );
    }
    return MapEntry(name, seconds.toDouble());
  });
}

Map<String, double> _optionalDoubleMap(
  Map<String, Object?> json,
  String key,
) {
  if (!json.containsKey(key)) {
    return {};
  }
  return _readDoubleMap(json, key);
}

Set<String> _readStringSet(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('Expected saved "$key" to be an array of strings.');
  }
  return value.cast<String>().toSet();
}
