import '../game/models/game_data.dart';

class ResearchEffectDescription {
  const ResearchEffectDescription({
    required this.category,
    required this.perLevel,
    required this.currentTotal,
    required this.nextTotal,
  });

  final String category;
  final String perLevel;
  final String currentTotal;
  final String? nextTotal;

  String get readableText => [
        category,
        perLevel,
        currentTotal,
        if (nextTotal != null) nextTotal!,
      ].join(' ');
}

ResearchEffectDescription describeEffect(
  ResearchData item,
  int level, {
  required String Function(double) formatNumber,
}) {
  final effectNames = item.effect
      .split('+')
      .map((effect) => _effectDefinition(effect).name)
      .join(' and ');
  final categories = item.effect
      .split('+')
      .map((effect) => _effectDefinition(effect).category)
      .toSet()
      .join(' + ');
  final isMultiplier = item.mode == 'mul';
  final isPercent = item.mode == 'add' ||
      (item.mode == null && _effectDefinition(item.effect).isPercent);

  String perLevel;
  String currentTotal;
  String? nextTotal;
  if (isMultiplier) {
    perLevel = '$effectNames ×${formatNumber(item.perLevel)} per level';
    currentTotal =
        'Now: ×${formatNumber(_multiplierTotal(item, level))} total $effectNames';
    nextTotal = level < item.maxLevel
        ? 'Next: ×${formatNumber(_multiplierTotal(item, level + 1))} total $effectNames'
        : null;
  } else if (isPercent) {
    final perLevelPercent = item.perLevel * 100;
    final currentPercent = item.perLevel * level * 100;
    perLevel = '+${formatNumber(perLevelPercent)}% $effectNames per level';
    currentTotal = 'Now: +${formatNumber(currentPercent)}% $effectNames';
    nextTotal = level < item.maxLevel
        ? 'Next: +${formatNumber(item.perLevel * (level + 1) * 100)}% $effectNames'
        : null;
  } else {
    final unit = _effectDefinition(item.effect).unit;
    final amountDescription = unit.isEmpty ? effectNames : unit;
    perLevel = '+${formatNumber(item.perLevel)} $amountDescription per level';
    currentTotal =
        'Now: +${formatNumber(item.perLevel * level)} $amountDescription';
    nextTotal = level < item.maxLevel
        ? 'Next: +${formatNumber(item.perLevel * (level + 1))} $amountDescription'
        : null;
  }

  return ResearchEffectDescription(
    category: categories,
    perLevel: perLevel,
    currentTotal: currentTotal,
    nextTotal: nextTotal,
  );
}

bool researchMatchesCategory(ResearchData item, String category) {
  if (category == 'All' || category == 'Affordable') {
    return true;
  }
  return item.effect.split('+').any(
        (effect) => _effectDefinition(effect).category == category,
      );
}

double _multiplierTotal(ResearchData item, int level) {
  if (level == 0) {
    return 1;
  }
  return _pow(item.perLevel, level);
}

double _pow(double value, int exponent) {
  var result = 1.0;
  for (var index = 0; index < exponent; index++) {
    result *= value;
  }
  return result;
}

class _EffectDefinition {
  const _EffectDefinition(
    this.name,
    this.category, {
    this.unit = '',
    this.isPercent = false,
  });

  final String name;
  final String category;
  final String unit;
  final bool isPercent;
}

_EffectDefinition _effectDefinition(String effect) {
  const definitions = <String, _EffectDefinition>{
    'layRate': _EffectDefinition('egg laying rate', 'Laying', isPercent: true),
    'eggValue': _EffectDefinition('egg value', 'Egg value'),
    'hatcheryRefill':
        _EffectDefinition('hatchery refill rate', 'Hatchery', isPercent: true),
    'runningBonusPerChicken': _EffectDefinition(
      'running-chicken bonus per chicken',
      'Running chickens',
      unit: 'bonus multiplier per chicken',
    ),
    'habCapacity':
        _EffectDefinition('habitat capacity', 'Housing', isPercent: true),
    'ihrPerHab': _EffectDefinition(
      'internal hatchery growth per habitat',
      'Hatchery',
      unit: 'chickens/min per habitat',
    ),
    'hatcheryCapacity': _EffectDefinition(
      'hatchery stock capacity',
      'Hatchery',
      unit: 'ready chickens',
    ),
    'vehicleCapacity':
        _EffectDefinition('vehicle capacity', 'Transport', isPercent: true),
    'fleetSize': _EffectDefinition('vehicle slots', 'Transport', unit: 'slots'),
    'maxRunningBonus': _EffectDefinition(
      'maximum running-chicken bonus',
      'Running chickens',
      unit: 'earnings multiplier cap',
    ),
    'vehicleSpeed':
        _EffectDefinition('vehicle speed', 'Transport', isPercent: true),
    'hoverVehicleCapacity': _EffectDefinition(
      'hover vehicle capacity',
      'Transport',
      isPercent: true,
    ),
    'portalHabCapacity': _EffectDefinition(
      'portal habitat capacity',
      'Housing',
      isPercent: true,
    ),
    'hyperloopVehicleCapacity': _EffectDefinition(
      'Hyperloop vehicle capacity',
      'Transport',
      isPercent: true,
    ),
    'holdHatchPerSec': _EffectDefinition(
      'hold-to-hatch speed',
      'Hatchery',
      unit: 'chickens/sec',
    ),
    'ihrMult': _EffectDefinition(
      'internal hatchery growth rate',
      'Hatchery',
      isPercent: true,
    ),
    'ihrAwayMult': _EffectDefinition(
      'internal hatchery growth while away',
      'Hatchery',
      isPercent: true,
    ),
    'habCostReduction': _EffectDefinition(
      'habitat price discount',
      'Housing',
      isPercent: true,
    ),
    'vehicleCostReduction': _EffectDefinition(
      'vehicle price discount',
      'Transport',
      isPercent: true,
    ),
    'researchCostReduction': _EffectDefinition(
      'research price discount',
      'Economy',
      isPercent: true,
    ),
    'siloMinutesPerSilo': _EffectDefinition(
      'offline time per silo',
      'Economy',
      unit: 'minutes per silo',
    ),
    'farmValueMult': _EffectDefinition(
      'farm value',
      'Economy',
      isPercent: true,
    ),
    'soulFood': _EffectDefinition(
      'earnings bonus per Soul Egg',
      'Prestige',
      isPercent: true,
    ),
    'prestigeBonus': _EffectDefinition(
      'Soul Egg gain',
      'Prestige',
      isPercent: true,
    ),
    'prophecyBonus': _EffectDefinition(
      'Candy Corn bonus strength',
      'Prestige',
      isPercent: true,
    ),
    'droneBigRewardChance': _EffectDefinition(
      'chance of larger drone rewards',
      'Drone rewards',
      isPercent: true,
    ),
    'layRate+eggValue': _EffectDefinition(
      'egg laying rate and egg value',
      'Laying',
      isPercent: true,
    ),
  };
  final definition = definitions[effect];
  if (definition == null) {
    throw ArgumentError.value(effect, 'effect', 'Unknown research effect.');
  }
  return definition;
}
