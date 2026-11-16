import 'dart:math' as math;

import 'engine.dart';
import 'models/game_data.dart';

enum PlotStatus { empty, growing, ready, withered }

class PlantedCrop {
  const PlantedCrop(this.cropId, this.plantedAtMs);

  final String cropId;
  final int plantedAtMs;
}

/// Everything the Garden saves. It survives prestige and egg upgrades.
class GardenState {
  GardenState({
    this.extraPlots = 0,
    this.lastSeenMs = 0,
    Map<int, PlantedCrop>? planted,
    Map<int, String>? lastCrops,
    Map<String, int>? harvested,
    Map<String, int>? boosts,
    Set<String>? unlockRewardsPaid,
  })  : planted = planted ?? {},
        lastCrops = lastCrops ?? {},
        harvested = harvested ?? {},
        boosts = boosts ?? {},
        unlockRewardsPaid = unlockRewardsPaid ?? {};

  /// Plots bought with Golden Eggs on top of the starter plots.
  int extraPlots;

  /// Latest clock reading seen; garden time never runs backwards from it.
  int lastSeenMs;
  final Map<int, PlantedCrop> planted;

  /// What each plot grew last, for "Replant same".
  final Map<int, String> lastCrops;

  /// Lifetime harvested units per crop.
  final Map<String, int> harvested;

  /// Harvested boosts waiting to be used, by boost id.
  final Map<String, int> boosts;

  /// Crops whose one-time unlock reward has been paid.
  final Set<String> unlockRewardsPaid;

  /// Unlock rewards just paid, waiting for the screen to announce them.
  /// Not saved.
  final List<({String cropName, double soulEggs})> newUnlockRewards = [];

  void reset() {
    extraPlots = 0;
    lastSeenMs = 0;
    planted.clear();
    lastCrops.clear();
    harvested.clear();
    boosts.clear();
    unlockRewardsPaid.clear();
    newUnlockRewards.clear();
  }

  /// Reads saved garden data; a save from before the Garden has none.
  factory GardenState.fromJson(Object? value, GameData data) {
    if (value == null) {
      return GardenState();
    }
    if (value is! Map<String, Object?>) {
      throw const FormatException('Saved garden must be a JSON object.');
    }
    final cropIds = data.garden.crops.map((crop) => crop.id).toSet();
    int count(Object? raw) {
      if (raw is! int || raw < 0) {
        throw const FormatException('Saved garden counts must be 0 or more.');
      }
      return raw;
    }

    Map<String, Object?> object(String key) {
      final raw = value[key] ?? const <String, Object?>{};
      if (raw is! Map<String, Object?>) {
        throw FormatException('Saved garden "$key" must be a JSON object.');
      }
      return raw;
    }

    final extraPlots = count(value['extraPlots'] ?? 0);
    final plotCount = math.min(
      data.garden.starterPlots + extraPlots,
      data.garden.maxPlots,
    );
    final planted = <int, PlantedCrop>{};
    for (final entry in object('planted').entries) {
      final plot = int.tryParse(entry.key);
      final crop = entry.value;
      // Crops removed from the config, or on plots that no longer exist, are
      // dropped rather than failing the whole save.
      if (plot == null ||
          plot < 0 ||
          plot >= plotCount ||
          crop is! Map<String, Object?> ||
          !cropIds.contains(crop['cropId'])) {
        continue;
      }
      planted[plot] = PlantedCrop(
        crop['cropId']! as String,
        count(crop['plantedAtMs']),
      );
    }
    return GardenState(
      extraPlots: plotCount - data.garden.starterPlots,
      lastSeenMs: count(value['lastSeenMs'] ?? 0),
      planted: planted,
      lastCrops: {
        for (final entry in object('lastCrops').entries)
          if (int.tryParse(entry.key) != null && cropIds.contains(entry.value))
            int.parse(entry.key): entry.value! as String,
      },
      harvested: {
        for (final entry in object('harvested').entries)
          entry.key: count(entry.value),
      },
      boosts: {
        for (final entry in object('boosts').entries)
          entry.key: count(entry.value),
      },
      unlockRewardsPaid: {
        for (final id in value['unlockRewardsPaid'] as List<Object?>? ?? [])
          if (id is String) id,
      },
    );
  }

  Map<String, Object?> toJson() => {
        'extraPlots': extraPlots,
        'lastSeenMs': lastSeenMs,
        'planted': {
          for (final entry in planted.entries)
            '${entry.key}': {
              'cropId': entry.value.cropId,
              'plantedAtMs': entry.value.plantedAtMs,
            },
        },
        'lastCrops': {
          for (final entry in lastCrops.entries) '${entry.key}': entry.value,
        },
        'harvested': harvested,
        'boosts': boosts,
        'unlockRewardsPaid': unlockRewardsPaid.toList(),
      };
}

/// TUNABLE: how harvested units count toward a crop's bonus. Linear for now;
/// change this one function to add diminishing returns.
double cropBonusScaling(double harvestedUnits) => harvestedUnits;

/// Garden rules. Plot state is always derived from timestamps, so it is right
/// however long the app was closed.
extension Garden on GameEngine {
  GardenData get _config => data.garden;
  GardenState get _garden => state.garden;

  int get gardenPlotCount => _config.starterPlots + _garden.extraPlots;

  /// Garden time in milliseconds. The device clock is the only clock we have,
  /// so this refuses to go backwards when the clock is set back.
  int gardenNow(DateTime deviceNow) => _garden.lastSeenMs = math.max(
        _garden.lastSeenMs,
        deviceNow.millisecondsSinceEpoch,
      );

  CropData crop(String cropId) =>
      _config.crops.firstWhere((crop) => crop.id == cropId);

  int cropReadyAtMs(PlantedCrop planted) =>
      planted.plantedAtMs + (crop(planted.cropId).growHours * 3600000).round();

  int cropWitherAtMs(PlantedCrop planted) =>
      cropReadyAtMs(planted) + (_config.witherMinutes * 60000).round();

  PlotStatus plotStatus(int plot, int nowMs) {
    final planted = _garden.planted[plot];
    if (planted == null) {
      return PlotStatus.empty;
    }
    if (nowMs < cropReadyAtMs(planted)) {
      return PlotStatus.growing;
    }
    return nowMs < cropWitherAtMs(planted)
        ? PlotStatus.ready
        : PlotStatus.withered;
  }

  int cropHarvested(String cropId) => _garden.harvested[cropId] ?? 0;

  bool isCropUnlocked(CropData crop) {
    final required = crop.unlockCropId;
    return required == null || cropHarvested(required) >= crop.unlockHarvests;
  }

  /// Seed price in cash: a fixed number of seconds of current earnings.
  double get seedCost => cashPerSecond * _config.seedCostEarningsSeconds;

  bool plantCrop(int plot, String cropId, int nowMs) {
    final cost = seedCost;
    if (plot < 0 ||
        plot >= gardenPlotCount ||
        _garden.planted.containsKey(plot) ||
        !isCropUnlocked(crop(cropId)) ||
        state.cash < cost) {
      return false;
    }
    state.cash -= cost;
    state.cashSpentThisRun += cost;
    _garden.planted[plot] = PlantedCrop(cropId, nowMs);
    _garden.lastCrops[plot] = cropId;
    return true;
  }

  /// Collects a ready crop. A second tap finds the plot empty and does nothing.
  bool harvestPlot(int plot, int nowMs) {
    if (plotStatus(plot, nowMs) != PlotStatus.ready) {
      return false;
    }
    final harvested = crop(_garden.planted.remove(plot)!.cropId);
    _garden.harvested[harvested.id] = cropHarvested(harvested.id) + 1;
    switch (harvested.reward) {
      case 'soulEggs':
        state.soulEggs += harvested.amount;
      case 'boost':
        final boostId = harvested.boostId!;
        _garden.boosts[boostId] = ownedGardenBoosts(boostId) + 1;
    }
    _payUnlockRewards(harvested.id);
    return true;
  }

  /// Pays the one-time reward of every crop this harvest count has unlocked.
  /// Checked on each harvest, so a count reached before the reward existed
  /// still pays on the next one.
  void _payUnlockRewards(String harvestedCropId) {
    for (final next in _config.crops) {
      if (next.unlockCropId != harvestedCropId ||
          cropHarvested(harvestedCropId) < next.unlockHarvests ||
          !_garden.unlockRewardsPaid.add(next.id)) {
        continue;
      }
      final reward = unlockReward(next);
      if (reward > 0) {
        state.soulEggs += reward;
        _garden.newUnlockRewards.add((cropName: next.name, soulEggs: reward));
      }
    }
  }

  /// Soul Eggs that unlocking [crop] would pay right now.
  double unlockReward(CropData crop) => math
      .max(
        crop.unlockRewardSoulEggFloor,
        (state.soulEggs * crop.unlockRewardSoulEggPercent / 100)
            .floorToDouble(),
      )
      .toDouble();

  /// Clears a withered crop for free; it yields nothing.
  bool clearPlot(int plot, int nowMs) {
    if (plotStatus(plot, nowMs) != PlotStatus.withered) {
      return false;
    }
    _garden.planted.remove(plot);
    return true;
  }

  /// Harvests every ready plot and clears every withered one.
  int harvestAll(int nowMs) {
    var harvested = 0;
    for (var plot = 0; plot < gardenPlotCount; plot++) {
      if (harvestPlot(plot, nowMs)) {
        harvested++;
      }
      clearPlot(plot, nowMs);
    }
    return harvested;
  }

  /// Replants each empty plot with what it grew last, while cash lasts.
  int replantAll(int nowMs) {
    var planted = 0;
    for (var plot = 0; plot < gardenPlotCount; plot++) {
      final cropId = _garden.lastCrops[plot];
      if (cropId != null && plantCrop(plot, cropId, nowMs)) {
        planted++;
      }
    }
    return planted;
  }

  /// Golden Egg price of the next plot, in a straight line from the first
  /// extra plot's price to the last one's.
  double get nextPlotPrice {
    final extraMax = _config.maxPlots - _config.starterPlots;
    final bought = _garden.extraPlots;
    if (bought >= extraMax) {
      return double.infinity;
    }
    if (extraMax == 1) {
      return _config.firstPlotPriceGoldenEggs;
    }
    return _config.firstPlotPriceGoldenEggs +
        (_config.lastPlotPriceGoldenEggs - _config.firstPlotPriceGoldenEggs) *
            bought /
            (extraMax - 1);
  }

  bool buyPlot() {
    final price = nextPlotPrice;
    if (state.goldenEggs < price) {
      return false;
    }
    state.goldenEggs -= price;
    _garden.extraPlots++;
    return true;
  }

  /// Prophecy-Egg-equivalents grown so far; the engine compounds earnings by
  /// this the way Prophecy Eggs did.
  double get gardenBonusUnits {
    var total = 0.0;
    for (final crop in _config.crops) {
      if (crop.reward == 'earningsBonus') {
        total +=
            cropBonusScaling(cropHarvested(crop.id).toDouble()) * crop.amount;
      }
    }
    return total;
  }

  int ownedGardenBoosts(String boostId) => _garden.boosts[boostId] ?? 0;

  /// Starts a harvested boost, exactly as if its option had been bought.
  bool useGardenBoost(String boostId) {
    final option = boostOptions(boostId)
        .where((candidate) => candidate.gardenOnly)
        .firstOrNull;
    final owned = ownedGardenBoosts(boostId);
    if (option == null || owned <= 0) {
      return false;
    }
    _garden.boosts[boostId] = owned - 1;
    state.activeBoostSeconds[boostId] = option.durationSeconds;
    state.activeBoostMultipliers[boostId] = option.multiplier;
    return true;
  }
}
