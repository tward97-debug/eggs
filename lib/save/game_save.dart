import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/balance.dart';
import '../game/engine.dart';
import '../game/models/game_data.dart';

class SavedGame {
  const SavedGame({
    required this.state,
    required this.lastSavedAt,
  });

  final GameState state;
  final DateTime lastSavedAt;
}

class GameSaveRepository {
  const GameSaveRepository();

  Future<SavedGame?> load(GameData data) async {
    final preferences = await SharedPreferences.getInstance();
    final serialized = preferences.getString(BalanceConfig.savePreferenceKey);
    if (serialized == null) {
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(serialized);
    } on FormatException catch (error) {
      throw FormatException(
          'The saved game is not valid JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('The saved game must be a JSON object.');
    }
    final version = decoded['version'];
    if (version != BalanceConfig.saveFormatVersion) {
      throw FormatException(
        'Unsupported save version $version; '
        'expected ${BalanceConfig.saveFormatVersion}.',
      );
    }
    final savedAtValue = decoded['lastSavedAt'];
    if (savedAtValue is! String) {
      throw const FormatException('The saved game is missing lastSavedAt.');
    }
    final savedAt = DateTime.tryParse(savedAtValue);
    if (savedAt == null) {
      throw const FormatException(
          'The saved lastSavedAt timestamp is invalid.');
    }
    final stateJson = decoded['state'];
    if (stateJson is! Map<String, Object?>) {
      throw const FormatException(
          'The saved game is missing its state object.');
    }
    return SavedGame(
      state: GameState.fromJson(stateJson, data),
      lastSavedAt: savedAt.toUtc(),
    );
  }

  Future<void> save(GameState state, DateTime savedAt) async {
    await saveSnapshot(state.toJson(), savedAt);
  }

  Future<void> saveSnapshot(
    Map<String, Object?> state,
    DateTime savedAt,
  ) async {
    final serialized = jsonEncode({
      'version': BalanceConfig.saveFormatVersion,
      'lastSavedAt': savedAt.toUtc().toIso8601String(),
      'state': state,
    });
    final preferences = await SharedPreferences.getInstance();
    final success = await preferences.setString(
      BalanceConfig.savePreferenceKey,
      serialized,
    );
    if (!success) {
      throw StateError('Could not persist the game save.');
    }
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    final success = await preferences.remove(BalanceConfig.savePreferenceKey);
    if (!success && preferences.containsKey(BalanceConfig.savePreferenceKey)) {
      throw StateError('Could not clear the game save.');
    }
  }
}
