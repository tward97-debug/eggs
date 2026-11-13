import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../config/balance.dart';
import '../game/engine.dart';
import '../game/models/game_data.dart';
import '../save/game_save.dart';

class GameSession extends ChangeNotifier {
  GameSession._({
    required this.engine,
    required GameSaveRepository saveRepository,
    required this.lastSavedAt,
    this.offlineProgress,
  }) : _saveRepository = saveRepository;

  static Future<GameSession> restore(
    GameData data, {
    GameSaveRepository saveRepository = const GameSaveRepository(),
    DateTime? now,
  }) async {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final savedGame = await saveRepository.load(data);
    if (savedGame == null) {
      final session = GameSession._(
        engine: GameEngine(data: data),
        saveRepository: saveRepository,
        lastSavedAt: currentTime,
      );
      await session.save(savedAt: currentTime);
      return session;
    }

    final engine = GameEngine(data: data, state: savedGame.state);
    final elapsedSeconds = math
        .max(
          0.0,
          currentTime.difference(savedGame.lastSavedAt).inMicroseconds /
              BalanceConfig.microsecondsPerSecond,
        )
        .toDouble();
    final progress = engine.simulateOffline(elapsedSeconds);
    final session = GameSession._(
      engine: engine,
      saveRepository: saveRepository,
      lastSavedAt: savedGame.lastSavedAt,
      offlineProgress: progress,
    );
    await session.save(savedAt: currentTime);
    return session;
  }

  final GameEngine engine;
  final GameSaveRepository _saveRepository;
  late final GameTicker _ticker = GameTicker(engine);
  DateTime lastSavedAt;
  OfflineProgress? offlineProgress;
  void Function(Object error)? onPersistenceError;

  double _holdAccumulator = 0;
  bool _isHoldingHatch = false;
  Timer? _autosaveTimer;
  Future<void> _saveTail = Future<void>.value();

  bool get isHoldingHatch => _isHoldingHatch;
  bool get isAutosaving => _autosaveTimer?.isActive ?? false;

  /// Hatches a tap-sized batch immediately, then continues while held.
  double startHatching() {
    final hatched = engine.hatch(requested: BalanceConfig.hatchTapBatchSize);
    _holdAccumulator = 0;
    _isHoldingHatch = canHatch;
    notifyListeners();
    return hatched;
  }

  /// Stops held hatching and discards a partial chicken from the old press.
  void stopHatching() {
    _isHoldingHatch = false;
    _holdAccumulator = 0;
    notifyListeners();
  }

  bool get canHatch =>
      engine.state.hatcheryStock > 0 &&
      engine.state.chickens < engine.totalHabCapacity;

  void refresh() {
    notifyListeners();
  }

  /// Advances fixed game ticks, held hatching, and refill only when released.
  double advance(double elapsedSeconds) {
    _ticker.advance(
      elapsedSeconds,
      refillHatchery: !_isHoldingHatch,
    );
    var hatched = 0.0;
    if (_isHoldingHatch) {
      final accumulatedChickens =
          _holdAccumulator + engine.holdHatchPerSecond * elapsedSeconds;
      final wholeChickens =
          (accumulatedChickens + BalanceConfig.fractionalChickenEpsilon)
              .floorToDouble();
      if (wholeChickens > 0) {
        hatched = engine.holdHatch(
          elapsedSeconds,
          accumulated: _holdAccumulator,
        );
        _holdAccumulator =
            math.max(0.0, accumulatedChickens - hatched).toDouble();
      } else {
        _holdAccumulator = accumulatedChickens;
      }
      if (!canHatch || hatched < wholeChickens) {
        _isHoldingHatch = false;
        _holdAccumulator = 0;
      }
    }
    notifyListeners();
    return hatched;
  }

  void setHapticsEnabled(bool enabled) {
    engine.state.hapticsEnabled = enabled;
    notifyListeners();
    _saveInBackground();
  }

  void startAutosave() {
    _autosaveTimer ??= Timer.periodic(
      Duration(seconds: BalanceConfig.autosaveIntervalSeconds),
      (_) => _saveInBackground(),
    );
  }

  void _saveInBackground() {
    unawaited(
      save().catchError((Object error, StackTrace stackTrace) {
        onPersistenceError?.call(error);
      }),
    );
  }

  Future<void> pause({DateTime? savedAt}) async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    stopHatching();
    await save(savedAt: savedAt);
  }

  Future<OfflineProgress> resume({DateTime? now}) async {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final elapsedSeconds = math
        .max(
          0.0,
          currentTime.difference(lastSavedAt).inMicroseconds /
              BalanceConfig.microsecondsPerSecond,
        )
        .toDouble();
    offlineProgress = engine.simulateOffline(elapsedSeconds);
    lastSavedAt = currentTime;
    await save(savedAt: currentTime);
    startAutosave();
    notifyListeners();
    return offlineProgress!;
  }

  Future<void> save({DateTime? savedAt}) {
    final timestamp = (savedAt ?? DateTime.now()).toUtc();
    final snapshot = engine.state.toJson();
    final operation = _saveTail
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .then((_) async {
      await _saveRepository.saveSnapshot(snapshot, timestamp);
      lastSavedAt = timestamp;
    });
    _saveTail = operation;
    return operation;
  }

  Future<void> resetAllData({DateTime? now}) async {
    stopHatching();
    engine.state.resetToNewGame();
    offlineProgress = null;
    lastSavedAt = (now ?? DateTime.now()).toUtc();
    await _saveRepository.clear();
    await save(savedAt: lastSavedAt);
    notifyListeners();
  }

  Future<void> close() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    stopHatching();
    await save();
  }
}
