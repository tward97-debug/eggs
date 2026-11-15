import 'dart:convert';

import 'package:flutter/services.dart';

import '../game/models/game_data.dart';

export '../game/models/game_data.dart';

class GameDataLoader {
  const GameDataLoader();

  Future<GameData> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final habJson = await _loadJson(assets, 'assets/data/habs.json');
    final vehicleJson = await _loadJson(assets, 'assets/data/vehicles.json');
    final eggJson = await _loadJson(assets, 'assets/data/eggs.json');
    final commonJson =
        _asObject(await _loadJson(assets, 'assets/data/common_research.json'));
    final epicJson =
        _asObject(await _loadJson(assets, 'assets/data/epic_research.json'));
    final boostJson = await _loadJson(assets, 'assets/data/boosts.json');

    final data = GameData(
      habs: _parseList(habJson, HabData.fromJson),
      vehicles: _parseList(vehicleJson, VehicleData.fromJson),
      eggs: _parseList(eggJson, EggData.fromJson),
      commonResearch: _parseList(
        _requiredList(commonJson, 'items'),
        (item) => ResearchData.fromJson(item, isEpic: false),
      ),
      epicResearch: _parseList(
        _requiredList(epicJson, 'items'),
        (item) => ResearchData.fromJson(item, isEpic: true),
      ),
      commonResearchTierUnlocks: parseIntegerList(
        _requiredList(commonJson, 'tierUnlockTotalLevels'),
        'common research tier unlocks',
      ),
      boosts: _parseList(boostJson, BoostData.fromJson),
    );
    data.validate();
    return data;
  }
}

Future<Object?> _loadJson(AssetBundle bundle, String path) async {
  final contents = await bundle.loadString(path);
  try {
    return jsonDecode(contents);
  } on FormatException catch (error) {
    throw FormatException('Invalid JSON in $path: ${error.message}');
  }
}

List<T> _parseList<T>(Object? value, T Function(Object?) parseItem) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON array.');
  }
  return value.map(parseItem).toList(growable: false);
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
