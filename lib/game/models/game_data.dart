class GameData {
  const GameData({
    required this.habs,
    required this.vehicles,
    required this.eggs,
    required this.commonResearch,
    required this.epicResearch,
    required this.commonResearchTierUnlocks,
    required this.boosts,
  });

  final List<HabData> habs;
  final List<VehicleData> vehicles;
  final List<EggData> eggs;
  final List<ResearchData> commonResearch;
  final List<ResearchData> epicResearch;
  final List<int> commonResearchTierUnlocks;
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
    if (boosts.any((boost) => boost.options.isEmpty)) {
      throw const FormatException('Every boost needs at least one option.');
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
    this.costs = const [],
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

  /// Common research only: the price of each level, in order.
  final List<double> costs;

  factory ResearchData.fromJson(Object? value, {required bool isEpic}) {
    final json = _asObject(value);
    final costs = isEpic
        ? const <double>[]
        : _numberList(_requiredList(json, 'costs'), 'costs');
    final maxLevel = _requiredInteger(json, 'maxLevel');
    if (!isEpic && costs.length != maxLevel) {
      throw FormatException(
        'Research ${_requiredString(json, 'id')} needs one cost per level.',
      );
    }
    return ResearchData(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      effect: _requiredString(json, 'effect'),
      perLevel: _requiredNumber(json, 'perLevel'),
      maxLevel: maxLevel,
      tier: isEpic ? null : _requiredInteger(json, 'tier'),
      mode: isEpic ? null : _requiredString(json, 'mode'),
      firstCost: isEpic ? _requiredNumber(json, 'firstCost') : costs.first,
      lastCost: isEpic ? _requiredNumber(json, 'lastCost') : costs.last,
      costs: costs,
    );
  }
}

class BoostData {
  const BoostData({
    required this.id,
    required this.name,
    required this.effect,
    required this.options,
  });

  final String id;
  final String name;
  final String effect;
  final List<BoostOption> options;

  factory BoostData.fromJson(Object? value) {
    final json = _asObject(value);
    final id = _requiredString(json, 'id');
    final options = _requiredList(json, 'options');
    return BoostData(
      id: id,
      name: _requiredString(json, 'name'),
      effect: _requiredString(json, 'effect'),
      options: [
        for (var index = 0; index < options.length; index++)
          BoostOption.fromJson(options[index], id: '$id:$index'),
      ],
    );
  }
}

class BoostOption {
  const BoostOption({
    required this.id,
    required this.label,
    required this.multiplier,
    required this.priceGoldenEggs,
    required this.durationSeconds,
  });

  final String id;
  final String label;
  final double multiplier;

  /// Unscaled wiki price; the engine applies the Golden Egg cost scale.
  final double priceGoldenEggs;
  final double durationSeconds;

  factory BoostOption.fromJson(Object? value, {required String id}) {
    final json = _asObject(value);
    return BoostOption(
      id: id,
      label: _requiredString(json, 'label'),
      multiplier: _requiredNumber(json, 'multiplier'),
      priceGoldenEggs: _requiredNumber(json, 'priceGoldenEggs'),
      durationSeconds: _requiredNumber(json, 'durationSeconds'),
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
