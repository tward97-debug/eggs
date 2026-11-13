class GameData {
  const GameData({
    required this.habs,
    required this.vehicles,
    required this.eggs,
    required this.commonResearch,
    required this.epicResearch,
    required this.commonResearchTierUnlocks,
    required this.commonResearchTierBaseCostGrowth,
    required this.commonResearchLevelCostCurveExponent,
    required this.boosts,
  });

  final List<HabData> habs;
  final List<VehicleData> vehicles;
  final List<EggData> eggs;
  final List<ResearchData> commonResearch;
  final List<ResearchData> epicResearch;
  final List<int> commonResearchTierUnlocks;
  final double commonResearchTierBaseCostGrowth;
  final double commonResearchLevelCostCurveExponent;
  final List<BoostData> boosts;

  void validate() {
    _requireUniqueIds(habs.map((item) => item.id), 'hab');
    _requireUniqueIds(vehicles.map((item) => item.id), 'vehicle');
    _requireUniqueIds(eggs.map((item) => item.id), 'egg');
    _requireUniqueIds(commonResearch.map((item) => item.id), 'common research');
    _requireUniqueIds(epicResearch.map((item) => item.id), 'epic research');
    _requireUniqueIds(boosts.map((item) => item.id), 'boost');

    if (habs.isEmpty || vehicles.isEmpty || eggs.isEmpty) {
      throw const FormatException(
          'Habs, vehicles, and eggs must not be empty.');
    }
    if (habs.any((hab) => hab.slotPrices.length != 4)) {
      throw const FormatException(
          'Every hab must have exactly four slot prices.');
    }
    if (commonResearchTierUnlocks.isEmpty ||
        commonResearchTierUnlocks.first != 0) {
      throw const FormatException(
        'Common research tier unlocks must start with zero.',
      );
    }
    if (!commonResearchTierBaseCostGrowth.isFinite ||
        commonResearchTierBaseCostGrowth <= 0 ||
        !commonResearchLevelCostCurveExponent.isFinite ||
        commonResearchLevelCostCurveExponent <= 0) {
      throw const FormatException(
        'Common research cost tuning values must be finite and positive.',
      );
    }
  }
}

class HabData {
  const HabData({
    required this.id,
    required this.name,
    required this.baseCapacity,
    required this.maxCapacityMultiplier,
    required this.slotPrices,
  });

  final String id;
  final String name;
  final double baseCapacity;
  final double maxCapacityMultiplier;
  final List<double> slotPrices;

  factory HabData.fromJson(Object? value) {
    final json = _asObject(value);
    final slotPrices = _numberList(
      _requiredList(json, 'slotPrices'),
      'slotPrices',
    );
    if (slotPrices.length != 4) {
      throw FormatException(
        'Hab ${_requiredString(json, 'id')} must have 4 prices.',
      );
    }
    return HabData(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      baseCapacity: _requiredNumber(json, 'baseCapacity'),
      maxCapacityMultiplier: _requiredNumber(json, 'maxCapacityMultiplier'),
      slotPrices: slotPrices,
    );
  }
}

class VehicleData {
  const VehicleData({
    required this.id,
    required this.name,
    required this.capacityPerMinute,
    required this.firstPrice,
  });

  final String id;
  final String name;
  final double capacityPerMinute;
  final double firstPrice;

  factory VehicleData.fromJson(Object? value) {
    final json = _asObject(value);
    return VehicleData(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      capacityPerMinute: _requiredNumber(json, 'capacityPerMinute'),
      firstPrice: _requiredNumber(json, 'firstPrice'),
    );
  }
}

class EggData {
  const EggData({
    required this.id,
    required this.name,
    required this.valuePerEgg,
    required this.upgradeFarmValue,
    required this.source,
  });

  final String id;
  final String name;
  final double valuePerEgg;
  final double? upgradeFarmValue;
  final String source;

  factory EggData.fromJson(Object? value) {
    final json = _asObject(value);
    final threshold = json['upgradeFarmValue'];
    if (threshold != null && threshold is! num) {
      throw FormatException(
        'Egg ${_requiredString(json, 'id')} has an invalid upgradeFarmValue.',
      );
    }
    return EggData(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      valuePerEgg: _requiredNumber(json, 'valuePerEgg'),
      upgradeFarmValue: (threshold as num?)?.toDouble(),
      source: _requiredString(json, 'source'),
    );
  }
}

class ResearchData {
  const ResearchData({
    required this.id,
    required this.name,
    required this.effect,
    required this.perLevel,
    required this.maxLevel,
    required this.tier,
    required this.mode,
    required this.firstCost,
    required this.lastCost,
  });

  final String id;
  final String name;
  final String effect;
  final double perLevel;
  final int maxLevel;
  final int? tier;
  final String? mode;
  final double firstCost;
  final double lastCost;

  factory ResearchData.fromJson(Object? value, {required bool isEpic}) {
    final json = _asObject(value);
    return ResearchData(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      effect: _requiredString(json, 'effect'),
      perLevel: _requiredNumber(json, 'perLevel'),
      maxLevel: _requiredInteger(json, 'maxLevel'),
      tier: isEpic ? null : _requiredInteger(json, 'tier'),
      mode: isEpic ? null : _requiredString(json, 'mode'),
      firstCost: _requiredNumber(json, 'firstCost'),
      lastCost: _requiredNumber(json, 'lastCost'),
    );
  }
}

class BoostData {
  const BoostData({
    required this.id,
    required this.name,
    required this.effect,
    required this.multiplier,
    required this.durationSeconds,
    required this.priceGoldenEggs,
  });

  final String id;
  final String name;
  final String effect;
  final double multiplier;
  final double durationSeconds;
  final double priceGoldenEggs;

  factory BoostData.fromJson(Object? value) {
    final json = _asObject(value);
    return BoostData(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      effect: _requiredString(json, 'effect'),
      multiplier: _requiredNumber(json, 'multiplier'),
      durationSeconds: _requiredNumber(json, 'durationSeconds'),
      priceGoldenEggs: _requiredNumber(json, 'priceGoldenEggs'),
    );
  }
}

Map<String, Object?> _asObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('Expected "$key" to be a JSON array.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected "$key" to be a non-empty string.');
  }
  return value;
}

double _requiredNumber(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('Expected "$key" to be a finite number.');
  }
  return value.toDouble();
}

int _requiredInteger(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('Expected "$key" to be an integer.');
  }
  return value;
}

List<double> _numberList(List<Object?> values, String label) {
  return values.map((value) {
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('Expected all $label values to be finite numbers.');
    }
    return value.toDouble();
  }).toList(growable: false);
}

List<int> parseIntegerList(List<Object?> values, String label) {
  return values.map((value) {
    if (value is! int) {
      throw FormatException('Expected all $label values to be integers.');
    }
    return value;
  }).toList(growable: false);
}

void _requireUniqueIds(Iterable<String> ids, String label) {
  final values = ids.toList();
  if (values.toSet().length != values.length) {
    throw FormatException('Duplicate $label ids were found.');
  }
}
