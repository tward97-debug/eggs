import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/balance.dart';
import '../data/game_data.dart';
import '../game/engine.dart';
import '../game/format_number.dart' as number_format;
import 'research_effect_description.dart';
import 'game_session.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.data,
    @visibleForTesting this.simulateDroneClockForTesting = false,
  });

  final GameData? data;
  final bool simulateDroneClockForTesting;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Future<GameData> _gameData = const GameDataLoader().load();

  @override
  Widget build(BuildContext context) {
    final suppliedData = widget.data;
    if (suppliedData != null) {
      return _LoadedGameScreen(
        data: suppliedData,
        simulateDroneClockForTesting: widget.simulateDroneClockForTesting,
      );
    }
    return FutureBuilder<GameData>(
      future: _gameData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Egg Empire')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Unable to load farm data: ${snapshot.error}'),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _LoadedGameScreen(
          data: data,
          simulateDroneClockForTesting: widget.simulateDroneClockForTesting,
        );
      },
    );
  }
}

class _DroneRewardEffect extends StatefulWidget {
  const _DroneRewardEffect({
    required this.message,
    required this.isGoldenEggReward,
    required this.onFinished,
    super.key,
  });

  final String message;
  final bool isGoldenEggReward;
  final VoidCallback onFinished;

  @override
  State<_DroneRewardEffect> createState() => _DroneRewardEffectState();
}

class _DroneRewardEffectState extends State<_DroneRewardEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward().whenComplete(widget.onFinished);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isGoldenEggReward ? Colors.amber : Colors.lightBlue;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = _controller.value;
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var index = 0; index < 8; index++)
                Transform.translate(
                  offset: Offset(
                    math.cos(index * math.pi / 4) * progress * 72,
                    math.sin(index * math.pi / 4) * progress * 72,
                  ),
                  child: Opacity(
                    opacity: 1 - progress,
                    child: Icon(Icons.auto_awesome, color: color, size: 18),
                  ),
                ),
              Transform.translate(
                offset: Offset(0, -progress * 90),
                child: Opacity(
                  opacity: 1 - progress,
                  child: Card(
                    color: color.withValues(alpha: 0.95),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Text(
                        widget.message,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoadedGameScreen extends StatefulWidget {
  const _LoadedGameScreen({
    required this.data,
    required this.simulateDroneClockForTesting,
  });

  final GameData data;
  final bool simulateDroneClockForTesting;

  @override
  State<_LoadedGameScreen> createState() => _LoadedGameScreenState();
}

class _LoadedGameScreenState extends State<_LoadedGameScreen> {
  late final Future<GameSession> _sessionFuture =
      GameSession.restore(widget.data);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GameSession>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Egg Empire')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Unable to load saved game: ${snapshot.error}'),
              ),
            ),
          );
        }
        final session = snapshot.data;
        if (session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _RunningGameScreen(
          data: widget.data,
          session: session,
          simulateDroneClockForTesting: widget.simulateDroneClockForTesting,
        );
      },
    );
  }
}

class _RunningGameScreen extends StatefulWidget {
  const _RunningGameScreen({
    required this.data,
    required this.session,
    required this.simulateDroneClockForTesting,
  });

  final GameData data;
  final GameSession session;
  final bool simulateDroneClockForTesting;

  @override
  State<_RunningGameScreen> createState() => _RunningGameScreenState();
}

class _RunningGameScreenState extends State<_RunningGameScreen>
    with WidgetsBindingObserver {
  GameSession get _session => widget.session;
  GameEngine get _engine => _session.engine;
  final Stopwatch _stopwatch = Stopwatch();
  final Stopwatch _hapticStopwatch = Stopwatch();
  Timer? _gameTimer;
  int _lastElapsedMilliseconds = 0;
  bool _isPausedForLifecycle = false;
  Future<void> _lifecycleWork = Future<void>.value();
  int _lastHapticMilliseconds =
      -BalanceConfig.hapticFeedbackThrottleMilliseconds;
  int _selectedPage = 0;
  bool _scientificNumberFormat = false;
  bool _showOfflineSummary = BalanceConfig.showOfflineSummaryDefault;
  String _researchFilter = 'All';
  int _droneRewardEffectSequence = 0;
  String? _droneRewardMessage;
  bool _droneRewardIsGoldenEgg = false;
  bool _droneTestSpawnScheduled = false;
  final math.Random _droneRandom = math.Random();
  late double _droneSecondsUntilSpawn = widget.simulateDroneClockForTesting
      ? 0
      : BalanceConfig.droneSpawnIntervalSec;
  double _droneFlightDuration = 0;
  double _droneFlightElapsed = 0;

  bool get _hasActiveDrone => _droneFlightDuration > 0;
  double get _droneFlightProgress => _hasActiveDrone
      ? (_droneFlightElapsed / _droneFlightDuration).clamp(0.0, 1.0)
      : 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.onPersistenceError = _showPersistenceError;
    _stopwatch.start();
    _hapticStopwatch.start();
    _scheduleNextDrone();
    _session.startAutosave();
    _startGameTimer();
    unawaited(_loadSettings());
  }

  void _startGameTimer() {
    _gameTimer ??= Timer.periodic(
      Duration(milliseconds: BalanceConfig.gameUiRefreshMilliseconds),
      _advanceGame,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gameTimer?.cancel();
    _stopwatch.stop();
    _session.onPersistenceError = null;
    unawaited(
      _lifecycleWork
          .then((_) => _session.close())
          .catchError((Object error, StackTrace stackTrace) {
        _showPersistenceError(error);
      }),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isPausedForLifecycle) {
        return;
      }
      _isPausedForLifecycle = false;
      _lastElapsedMilliseconds = _stopwatch.elapsedMilliseconds;
      _lifecycleWork = _lifecycleWork.then((_) => _resumeGame());
      return;
    }
    if (_isPausedForLifecycle) {
      return;
    }
    _isPausedForLifecycle = true;
    _gameTimer?.cancel();
    _gameTimer = null;
    _droneFlightDuration = 0;
    _droneFlightElapsed = 0;
    _droneSecondsUntilSpawn = BalanceConfig.droneSpawnIntervalSec;
    _lifecycleWork = _lifecycleWork.then((_) => _pauseAndSave());
  }

  Future<void> _pauseAndSave() async {
    try {
      await _session.pause();
    } catch (error) {
      _showPersistenceError(error);
    }
  }

  Future<void> _resumeGame() async {
    late final OfflineProgress progress;
    try {
      progress = await _session.resume();
    } catch (error) {
      _showGameError('Unable to resume game', error);
      if (mounted) {
        _startGameTimer();
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _startGameTimer();
    if (_showOfflineSummary &&
        progress.elapsedSeconds >
            BalanceConfig.offlineWelcomeBackThresholdSeconds) {
      await _showWelcomeBack(progress);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) {
        return;
      }
      setState(() {
        _scientificNumberFormat =
            preferences.getBool(BalanceConfig.numberFormatPreferenceKey) ??
                false;
        _showOfflineSummary =
            preferences.getBool(BalanceConfig.offlineSummaryPreferenceKey) ??
                BalanceConfig.showOfflineSummaryDefault;
      });
      final progress = _session.offlineProgress;
      if (_showOfflineSummary &&
          progress != null &&
          progress.elapsedSeconds >
              BalanceConfig.offlineWelcomeBackThresholdSeconds) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showWelcomeBack(progress);
          }
        });
      }
    } catch (error) {
      _showGameError('Unable to load settings', error);
    }
  }

  Future<void> _setNumberFormat(bool scientific) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(
        BalanceConfig.numberFormatPreferenceKey,
        scientific,
      );
      if (!saved) {
        throw StateError('Could not save number-format preference.');
      }
      if (mounted) {
        setState(() => _scientificNumberFormat = scientific);
      }
    } catch (error) {
      _showGameError('Unable to save settings', error);
    }
  }

  Future<void> _setOfflineSummary(bool enabled) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(
        BalanceConfig.offlineSummaryPreferenceKey,
        enabled,
      );
      if (!saved) {
        throw StateError('Could not save offline-summary preference.');
      }
      if (mounted) {
        setState(() => _showOfflineSummary = enabled);
      }
    } catch (error) {
      _showGameError('Unable to save settings', error);
    }
  }

  String formatNumber(double value) => number_format.formatNumber(
        value,
        scientific: _scientificNumberFormat,
      );

  void _showPersistenceError(Object error) {
    _showGameError('Unable to save game', error);
  }

  void _showGameError(String message, Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$message: $error')),
    );
  }

  Future<void> _showWelcomeBack(OfflineProgress progress) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Welcome back!'),
        content: Text(
          'Your farm earned ${formatNumber(progress.cashEarned)} while you '
          'were away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _advanceGame(Timer timer) {
    final elapsedMilliseconds = _stopwatch.elapsedMilliseconds;
    var deltaMilliseconds = elapsedMilliseconds - _lastElapsedMilliseconds;
    if (widget.simulateDroneClockForTesting) {
      deltaMilliseconds = BalanceConfig.gameUiRefreshMilliseconds;
    }
    _lastElapsedMilliseconds = elapsedMilliseconds;
    if (deltaMilliseconds > 0 && mounted) {
      final elapsedSeconds =
          deltaMilliseconds / BalanceConfig.millisecondsPerSecond;
      final chickensHatched = _session.advance(
        elapsedSeconds,
      );
      _advanceDrone(elapsedSeconds);
      if (chickensHatched > 0) {
        _provideHapticFeedback();
      }
    }
  }

  void _advanceDrone(double elapsedSeconds) {
    if (_selectedPage != 0) {
      return;
    }
    if (_hasActiveDrone) {
      _droneFlightElapsed += elapsedSeconds;
      if (_droneFlightElapsed >= _droneFlightDuration) {
        _droneFlightDuration = 0;
        _droneFlightElapsed = 0;
        _scheduleNextDrone();
      }
      return;
    }
    _droneSecondsUntilSpawn -= elapsedSeconds;
    if (_droneSecondsUntilSpawn <= 0) {
      _droneFlightDuration = BalanceConfig.droneFlightDurationSec;
      _droneFlightElapsed = 0;
    }
  }

  void _scheduleNextDrone() {
    if (widget.simulateDroneClockForTesting) {
      _droneSecondsUntilSpawn = _droneTestSpawnScheduled ? double.infinity : 0;
      _droneTestSpawnScheduled = true;
      return;
    }
    final jitter = (2 * _droneRandom.nextDouble() - 1) *
        BalanceConfig.droneSpawnJitterFraction;
    _droneSecondsUntilSpawn =
        BalanceConfig.droneSpawnIntervalSec * (1 + jitter);
  }

  void _collectDrone() {
    final speed = (1 - _droneFlightProgress).clamp(0.0, 1.0);
    final reward = _engine.collectDrone(
      rewardRoll: _droneRandom.nextDouble(),
      tierRoll: _droneRandom.nextDouble(),
      eliteRoll: _droneRandom.nextDouble(),
      speed: speed,
    );
    _droneFlightDuration = 0;
    _droneFlightElapsed = 0;
    _scheduleNextDrone();
    _droneRewardMessage = reward.isGoldenEggReward
        ? '+${formatNumber(reward.goldenEggs)} Golden Eggs'
        : '+${formatNumber(reward.cash)} cash';
    _droneRewardIsGoldenEgg = reward.isGoldenEggReward;
    _droneRewardEffectSequence++;
    _session.refresh();
    setState(() {});
  }

  void _dismissDroneRewardEffect(int sequence) {
    if (!mounted || sequence != _droneRewardEffectSequence) {
      return;
    }
    setState(() => _droneRewardMessage = null);
  }

  void _startHatching() {
    if (_session.startHatching() > 0) {
      _provideHapticFeedback();
    }
  }

  void _provideHapticFeedback() {
    if (!_engine.state.hapticsEnabled ||
        _hapticStopwatch.elapsedMilliseconds - _lastHapticMilliseconds <
            BalanceConfig.hapticFeedbackThrottleMilliseconds) {
      return;
    }
    _lastHapticMilliseconds = _hapticStopwatch.elapsedMilliseconds;
    unawaited(HapticFeedback.lightImpact());
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameSession>.value(
      value: _session,
      child: Consumer<GameSession>(
        builder: (context, session, _) => _buildScaffold(session),
      ),
    );
  }

  Widget _buildScaffold(GameSession session) {
    final pages = [
      _buildFarmPage(),
      _buildResearchPage(),
      _buildPrestigePage(),
      _buildTrophiesPage(),
      _buildBoostsPage(),
      _buildSettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Egg Empire'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Egg tier ${session.engine.eggIndex + 1}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: IndexedStack(
              index: _selectedPage,
              children: pages,
            ),
          ),
          if (_droneRewardMessage case final message?)
            Positioned.fill(
              child: IgnorePointer(
                child: _DroneRewardEffect(
                  key: ValueKey(_droneRewardEffectSequence),
                  message: message,
                  isGoldenEggReward: _droneRewardIsGoldenEgg,
                  onFinished: () => _dismissDroneRewardEffect(
                    _droneRewardEffectSequence,
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedPage,
        onDestinationSelected: (index) {
          setState(() => _selectedPage = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.agriculture_outlined),
            selectedIcon: Icon(Icons.agriculture),
            label: 'Farm',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Research',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Prestige',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Trophies',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Boosts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildFarmPage() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildFarmCashPanel(theme),
        if (_engine.eggsBackingUp)
          Card(
            color: theme.colorScheme.errorContainer,
            child: const ListTile(
              leading: Icon(Icons.warning_amber_rounded),
              title: Text('Eggs are backing up'),
              subtitle: Text('Add transport capacity to ship the whole flock.'),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Chickens: ${formatNumber(_engine.state.chickens)}'
                  ' / ${formatNumber(_engine.totalHabCapacity)}',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatNumber(_engine.eggsLaidPerMinute)} eggs/min laid · '
                  '${formatNumber(_engine.shipCapacityPerMinute)} eggs/min '
                  'transport',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value:
                      (_engine.state.hatcheryStock / _engine.hatcheryCapacity)
                          .clamp(
                            BalanceConfig.hatcheryProgressMinimum,
                            BalanceConfig.hatcheryProgressMaximum,
                          )
                          .toDouble(),
                  semanticsLabel: 'Hatchery stock',
                ),
                const SizedBox(height: 8),
                Text(
                  'Ready chickens: '
                  '${formatNumber(_engine.state.hatcheryStock)} / '
                  '${formatNumber(_engine.hatcheryCapacity)}',
                ),
                const SizedBox(height: 8),
                Listener(
                  onPointerDown: (_) => _startHatching(),
                  onPointerUp: (_) => _session.stopHatching(),
                  onPointerCancel: (_) => _session.stopHatching(),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.egg_alt),
                      label: Text(
                        'Tap to hatch '
                        '${formatNumber(BalanceConfig.hatchTapBatchSize)} '
                        'or hold',
                      ),
                    ),
                  ),
                ),
                Text(
                  'Holding hatches '
                  '${formatNumber(_engine.holdHatchPerSecond)} chickens/sec',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Internal hatcheries: '
                  '${formatNumber(_engine.flatResearchBonus('ihrPerHab'))} '
                  'chickens/min per habitat',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: BalanceConfig.managementMenuItemSpacing),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('open-habitats'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.fromHeight(
                            BalanceConfig.managementButtonMinimumHeight,
                          ),
                        ),
                        onPressed: _showHabitatsMenu,
                        icon: const Icon(Icons.home_work_outlined),
                        label: const Text('Habitats'),
                      ),
                    ),
                    const SizedBox(
                      width: BalanceConfig.managementMenuItemSpacing,
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('open-transport'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.fromHeight(
                            BalanceConfig.managementButtonMinimumHeight,
                          ),
                        ),
                        onPressed: _showTransportMenu,
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Transport'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFarmCashPanel(ThemeData theme) {
    return Card(
      key: const ValueKey('farm-cash-panel'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Padding(
              key: const ValueKey('cash-panel-text-reserved-space'),
              padding: const EdgeInsets.only(
                right: BalanceConfig.droneCashTextRightPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Farm cash', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    formatNumber(_engine.state.cash),
                    style: theme.textTheme.headlineMedium,
                  ),
                  Text('${formatNumber(_engine.cashPerSecond)}/sec'),
                  Text(
                    'Running chicken bonus ×'
                    '${formatNumber(_engine.runningChickenMultiplier)} · '
                    '${formatNumber(_engine.runningChickenCount)} runners',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (_engine.nextEggUpgradeFarmValue case final threshold?)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Farm value: ${formatNumber(_engine.farmValue)} / '
                          '${formatNumber(threshold)}',
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (_engine.farmValue / threshold)
                              .clamp(
                                BalanceConfig.hatcheryProgressMinimum,
                                BalanceConfig.hatcheryProgressMaximum,
                              )
                              .toDouble(),
                          semanticsLabel: 'Farm value progress',
                        ),
                      ],
                    )
                  else
                    Text('Farm value: ${formatNumber(_engine.farmValue)}'),
                  if (_engine.canAscend)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _confirmAscend,
                        icon: const Icon(Icons.arrow_upward),
                        label: Text(
                          'Ascend to egg tier ${_engine.eggIndex + 2}',
                        ),
                      ),
                    ),
                  const Divider(height: 28),
                  Text(
                    'Egg tier ${_engine.eggIndex + 1} · '
                    '${formatNumber(_engine.currentEgg.valuePerEgg)} per egg',
                  ),
                ],
              ),
            ),
            if (_hasActiveDrone)
              Positioned(
                top: 0,
                right: 0,
                child: SizedBox(
                  width: BalanceConfig.droneButtonDiameter,
                  height: BalanceConfig.droneButtonDiameter,
                  child: FilledButton(
                    key: const ValueKey('drone-button'),
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _collectDrone,
                    child: const Text(
                      'Drone',
                      style: TextStyle(
                        fontSize: BalanceConfig.droneButtonLabelFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAscend() async {
    final nextTier = _engine.eggIndex + 2;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ascend to a new egg tier?'),
        content: Text(
          'This starts a new farm on egg tier $nextTier. '
          'Your prestige earnings are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ascend'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _mutate(_engine.ascend);
      try {
        await _session.save();
      } catch (error) {
        _showPersistenceError(error);
      }
    }
  }

  Future<void> _showHabitatsMenu() => _showManagementMenu(
        title: 'Habitats',
        icon: Icons.home_work_outlined,
        children: (setSheetState) => [
          for (var tier = 0; tier < widget.data.habs.length; tier++)
            _buildHabitatTierRow(tier, setSheetState: setSheetState),
        ],
      );

  Future<void> _showTransportMenu() => _showManagementMenu(
        title: 'Transport',
        icon: Icons.local_shipping_outlined,
        children: (setSheetState) => [
          Card(
            child: ListTile(
              title: const Text('Shipping capacity'),
              subtitle: Text(
                '${formatNumber(_engine.shipCapacityPerMinute)} eggs/min · '
                '${_engine.state.vehicles.length}/'
                '${formatNumber(_engine.maximumFleetSize)} slots used',
              ),
            ),
          ),
          for (var tier = 0; tier < widget.data.vehicles.length; tier++)
            _buildVehicleTierRow(tier, setSheetState: setSheetState),
        ],
      );

  Future<void> _showManagementMenu({
    required String title,
    required IconData icon,
    required List<Widget> Function(StateSetter) children,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: BalanceConfig.managementSheetHeightFraction,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BalanceConfig.managementMenuContentPadding,
                  vertical: BalanceConfig.managementMenuItemSpacing,
                ),
                child: Row(
                  children: [
                    Icon(icon),
                    const SizedBox(
                      width: BalanceConfig.managementMenuItemSpacing,
                    ),
                    Expanded(
                      child: Text(
                        title,
                        key: const ValueKey('management-menu-title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close $title',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BalanceConfig.managementMenuContentPadding,
                ),
                child: Text(
                  'Farm cash: ${formatNumber(_engine.state.cash)} · '
                  '${formatNumber(_engine.cashPerSecond)}/sec',
                  key: const ValueKey('management-cash-header'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: BalanceConfig.managementMenuItemSpacing),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(
                    BalanceConfig.managementMenuContentPadding,
                  ),
                  children: children(setSheetState),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _nextHabitatTierPrice(int tier) {
    if (tier == 0) {
      final availableSlots = List<int>.generate(
        BalanceConfig.maximumHabCount,
        (index) => index,
      ).where(
        (slotIndex) =>
            !_engine.state.habs.any((hab) => hab.slotIndex == slotIndex),
      );
      final prices = availableSlots
          .map((slotIndex) => _engine.habPrice(0, slotIndex: slotIndex))
          .toList();
      return prices.isEmpty ? double.infinity : prices.reduce(math.min);
    }

    final prices = _engine.state.habs
        .where((hab) => hab.tierIndex < tier)
        .map((hab) => widget.data.habs[tier].slotPrices[hab.slotIndex])
        .toList();
    return prices.isEmpty ? double.infinity : prices.reduce(math.min);
  }

  Widget _buildHabitatTierRow(
    int tier, {
    required StateSetter? setSheetState,
  }) {
    final habitat = widget.data.habs[tier];
    final owned =
        _engine.state.habs.where((hab) => hab.tierIndex == tier).length;
    final price = _nextHabitatTierPrice(tier);
    final canBuy = price.isFinite && _engine.state.cash >= price;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          BalanceConfig.managementMenuContentPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(habitat.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: BalanceConfig.managementMenuItemSpacing),
            Text('$owned / ${BalanceConfig.maximumHabCount} owned'),
            Text(
              '${formatNumber(_engine.capacityForHab(tier))} chickens capacity',
            ),
            const SizedBox(height: BalanceConfig.managementMenuItemSpacing),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Next: ${price.isFinite ? '${formatNumber(price)} cash' : 'Unavailable'}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: BalanceConfig.researchMinimumTextSize,
                    ),
                  ),
                ),
                FilledButton(
                  key: ValueKey('buy-habitat-tier-$tier'),
                  onPressed: canBuy
                      ? () => _buyHabitatTier(
                            tier,
                            setSheetState: setSheetState,
                          )
                      : null,
                  child: const Text('Buy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTierRow(
    int tier, {
    required StateSetter? setSheetState,
  }) {
    final vehicle = widget.data.vehicles[tier];
    final owned =
        _engine.state.vehicles.where((item) => item.tierIndex == tier).length;
    final price = _engine.vehicleUpgradePrice(tier);
    final freeTierAlreadyOwned = vehicle.firstPrice == 0 && owned > 0;
    final hasSlot = _engine.state.vehicles.length < _engine.maximumFleetSize;
    final canBuy =
        hasSlot && !freeTierAlreadyOwned && _engine.state.cash >= price;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          BalanceConfig.managementMenuContentPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vehicle.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: BalanceConfig.managementMenuItemSpacing),
            Text(
              '$owned / ${formatNumber(_engine.maximumFleetSize)} owned',
            ),
            Text(
              '${formatNumber(_engine.capacityForVehicle(tier))} eggs/min capacity',
            ),
            const SizedBox(height: BalanceConfig.managementMenuItemSpacing),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Next: ${formatNumber(price)} cash',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: BalanceConfig.researchMinimumTextSize,
                    ),
                  ),
                ),
                FilledButton(
                  key: ValueKey('buy-vehicle-tier-$tier'),
                  onPressed: canBuy
                      ? () => _buyVehicleTier(
                            tier,
                            setSheetState: setSheetState,
                          )
                      : null,
                  child: const Text('Buy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _buyVehicleTier(int tier, {required StateSetter? setSheetState}) {
    _mutate(() => _engine.buyVehicle(tier));
    setSheetState?.call(() {});
  }

  Widget _buildCashBalanceHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        key: const ValueKey('cash-balance-header'),
        child: ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Farm cash'),
          subtitle: Text('${formatNumber(_engine.cashPerSecond)}/sec'),
          trailing: Text(
            formatNumber(_engine.state.cash),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }

  Future<void> _buyHabitatTier(
    int tier, {
    required StateSetter? setSheetState,
  }) async {
    if (tier == 0) {
      final slotIndex = List<int>.generate(
        BalanceConfig.maximumHabCount,
        (index) => index,
      ).firstWhere(
        (slotIndex) =>
            !_engine.state.habs.any((hab) => hab.slotIndex == slotIndex),
        orElse: () => -1,
      );
      if (slotIndex >= 0) {
        _mutate(() => _engine.buyHab(0, slotIndex: slotIndex));
        setSheetState?.call(() {});
      }
      return;
    }

    final eligibleHabs =
        _engine.state.habs.where((hab) => hab.tierIndex < tier).toList();
    final slotIndex = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Upgrade to ${widget.data.habs[tier].name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final hab in eligibleHabs)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: BalanceConfig.managementMenuItemSpacing,
                    ),
                    child: OutlinedButton(
                      onPressed: _engine.state.cash >=
                              widget.data.habs[tier].slotPrices[hab.slotIndex]
                          ? () => Navigator.of(dialogContext).pop(hab.slotIndex)
                          : null,
                      child: Text(
                        'Habitat ${hab.slotIndex + 1} · '
                        'Tier ${hab.tierIndex + 1} · '
                        '${formatNumber(widget.data.habs[tier].slotPrices[hab.slotIndex])} cash',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (slotIndex != null && mounted) {
      final hab = _engine.state.habs.firstWhere(
        (item) => item.slotIndex == slotIndex,
      );
      _mutate(
        () => _engine.upgradeHab(
          hab.tierIndex,
          slotIndex,
          targetTierIndex: tier,
        ),
      );
      setSheetState?.call(() {});
    }
  }

  Widget _buildResearchPage() {
    final items = widget.data.commonResearch;
    final tiers =
        items.map((item) => item.tier!).toSet().toList(growable: false)..sort();
    return Column(
      children: [
        _buildCashBalanceHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in BalanceConfig.researchCategories)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: BalanceConfig.researchFilterSpacing,
                        ),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: _researchFilter == category,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) =>
                              setState(() => _researchFilter = category),
                        ),
                      ),
                  ],
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Golden Eggs'),
                  trailing: Text(
                    formatNumber(_engine.state.goldenEggs),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.science),
                  title: const Text('Common research'),
                  subtitle: const Text('Research upgrades grouped by tier.'),
                ),
              ),
              for (final tier in tiers)
                _buildResearchTier(
                  tier,
                  items.where((item) {
                    if (item.tier != tier ||
                        !researchMatchesCategory(item, _researchFilter)) {
                      return false;
                    }
                    return _researchFilter != 'Affordable' ||
                        (_engine.isCommonResearchTierUnlocked(tier) &&
                            (_engine.state.commonResearchLevels[item.id] ?? 0) <
                                item.maxLevel &&
                            _engine.state.cash >=
                                _engine.commonResearchCost(item.id));
                  }).toList(growable: false),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Epic research'),
                  subtitle: Text(
                    'Golden Eggs · '
                    '${formatNumber(_engine.state.goldenEggs)} available',
                  ),
                ),
              ),
              for (final item in widget.data.epicResearch.where((item) {
                if (!researchMatchesCategory(item, _researchFilter)) {
                  return false;
                }
                return _researchFilter != 'Affordable' ||
                    (_engine.epicResearchLevel(item.id) < item.maxLevel &&
                        _engine.state.goldenEggs >=
                            _engine.epicResearchCost(item.id));
              }))
                _buildEpicResearchItem(item),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEpicResearchItem(ResearchData item) {
    final level = _engine.epicResearchLevel(item.id);
    final cost = _engine.epicResearchCost(item.id);
    final maxed = level >= item.maxLevel;
    return _buildResearchCard(
      item: item,
      level: level,
      cost: cost,
      currency: 'GE',
      maxed: maxed,
      affordable: !maxed && _engine.state.goldenEggs >= cost,
      onBuy: () => _mutate(() => _engine.buyEpicResearch(item.id)),
    );
  }

  Widget _buildResearchCard({
    required ResearchData item,
    required int level,
    required double cost,
    required String currency,
    required bool maxed,
    required bool affordable,
    required VoidCallback onBuy,
    String? lockedRequirement,
  }) {
    final description = describeEffect(
      item,
      level,
      formatNumber: formatNumber,
    );
    final locked = lockedRequirement != null;
    final dimmed = locked || (!maxed && !affordable);
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: dimmed ? 0.68 : 1,
      child: Card(
        key: ValueKey('research-item-${item.id}'),
        color: maxed ? colors.surfaceContainerLow : null,
        child: Padding(
          padding: const EdgeInsets.all(BalanceConfig.researchCardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      right: BalanceConfig.researchRowSpacing,
                    ),
                    child: Icon(
                      _researchCategoryIcon(description.category),
                      size: 20,
                      semanticLabel: description.category,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  Text(
                    '$level / ${item.maxLevel}',
                    key: ValueKey('research-level-${item.id}'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: BalanceConfig.researchMinimumTextSize,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: BalanceConfig.researchCardPadding,
                  top: BalanceConfig.researchRowSpacing,
                ),
                child: Text(
                  description.category,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: BalanceConfig.researchRowSpacing),
              _researchBodyText('Per level: ${description.perLevel}'),
              _researchBodyText(description.currentTotal),
              if (description.nextTotal case final next?)
                _researchBodyText(next),
              if (lockedRequirement case final requirement?)
                Padding(
                  padding: const EdgeInsets.only(
                    top: BalanceConfig.researchRowSpacing,
                  ),
                  child: _researchBodyText(requirement),
                ),
              const SizedBox(height: BalanceConfig.researchRowSpacing),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      maxed
                          ? 'MAX'
                          : 'Next cost: ${formatNumber(cost)} $currency',
                      key: ValueKey('research-cost-${item.id}'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: BalanceConfig.researchMinimumTextSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (maxed)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, color: colors.outline),
                        Text(
                          'MAX',
                          style: TextStyle(color: colors.outline),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      height: BalanceConfig.researchButtonMinimumHeight,
                      child: FilledButton(
                        onPressed: affordable && !locked ? onBuy : null,
                        child: const Text('Buy'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _researchBodyText(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: BalanceConfig.researchMinimumTextSize,
        ),
      );

  IconData _researchCategoryIcon(String category) => switch (category) {
        'Laying' => Icons.egg_alt_outlined,
        'Egg value' => Icons.payments_outlined,
        'Housing' => Icons.home_work_outlined,
        'Transport' => Icons.local_shipping_outlined,
        'Hatchery' => Icons.egg_alt_outlined,
        'Running chickens' => Icons.directions_run,
        'Prestige' => Icons.auto_awesome,
        'Drone rewards' => Icons.flight,
        _ => Icons.tune,
      };

  Widget _buildPrestigePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Soul Eggs'),
            subtitle: Text(
              '${formatNumber(_engine.state.soulEggs)} owned · '
              '${formatNumber(_engine.soulEggsGained)} gained on prestige',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.stars),
            title: const Text('Earnings bonus'),
            subtitle: Text(
              '${formatNumber(_engine.earningsBonus * 100)}% bonus · '
              '×${formatNumber(_engine.earningsMultiplier)} income',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Prophecy Eggs'),
            subtitle: Text(formatNumber(_engine.state.prophecyEggs)),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Soul Food'),
            subtitle: Text(
              'Level ${_engine.epicResearchLevel('soul_food')} · '
              '${formatNumber(_engine.perSoulEggEarningsBonus)} per Soul Egg',
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Prophecy Bonus'),
            subtitle: Text(
              'Level ${_engine.epicResearchLevel('prophecy_bonus')} · '
              '×${formatNumber(_engine.prophecyEggMultiplier)} per '
              'Prophecy Egg',
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _confirmPrestige,
          icon: const Icon(Icons.refresh),
          label: Text(
            'Prestige for ${formatNumber(_engine.soulEggsGained)} Soul Eggs',
          ),
        ),
      ],
    );
  }

  Widget _buildBoostsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.bolt),
            title: const Text('Temporary boosts'),
            subtitle: Text(
              '${formatNumber(_engine.state.goldenEggs)} Golden Eggs '
              'available. Boosts continue counting down while you are away.',
            ),
          ),
        ),
        for (final boost in widget.data.boosts) _buildBoostCard(boost),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (BalanceConfig.piggyBankEnabled)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Piggy Bank',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${formatNumber(_engine.state.piggyBankGoldenEggs)} '
                    'Golden Eggs stored',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _engine.state.piggyBankGoldenEggs > 0
                        ? () => _mutate(_engine.crackPiggyBank)
                        : null,
                    child: const Text('Crack Piggy Bank'),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Scientific number format'),
                subtitle: const Text('Display values like 1.23e+6'),
                value: _scientificNumberFormat,
                onChanged: _setNumberFormat,
              ),
              SwitchListTile(
                title: const Text('Offline summary'),
                subtitle: const Text('Show earnings when you return'),
                value: _showOfflineSummary,
                onChanged: _setOfflineSummary,
              ),
              SwitchListTile(
                key: const ValueKey('haptics-setting'),
                title: const Text('Haptic feedback'),
                subtitle: const Text('Vibrate when chickens hatch.'),
                value: _engine.state.hapticsEnabled,
                onChanged: _session.setHapticsEnabled,
              ),
            ],
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Reset all data'),
            subtitle: const Text('Start a new game and erase saved progress.'),
            trailing: FilledButton.tonal(
              onPressed: _confirmResetAllData,
              child: const Text('Reset'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmResetAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all game data?'),
        content: const Text(
          'This permanently erases your farm, upgrades, and saved progress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _session.resetAllData();
    } catch (error) {
      _showGameError('Unable to reset game data', error);
    }
  }

  Widget _buildBoostCard(BoostData boost) {
    final remaining = _engine.state.activeBoostSeconds[boost.id] ?? 0;
    final activeMultiplier =
        remaining > 0 ? _engine.activeBoostMultiplier(boost.effect) : 1.0;
    final options = _engine.boostOptions(boost.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(boost.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              remaining > 0
                  ? 'Active · ×${formatNumber(activeMultiplier)} · '
                      '${_formatBoostTime(remaining)} remaining'
                  : '${_boostEffectLabel(boost.effect)} · '
                      '${_formatBoostTime(boost.durationSeconds)} duration',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  OutlinedButton(
                    onPressed:
                        _engine.state.goldenEggs >= option.priceGoldenEggs
                            ? () => _mutate(
                                  () => _engine.buyBoost(boost.id, option.id),
                                )
                            : null,
                    child: Text(
                      '${option.label}\n'
                      '${formatNumber(option.priceGoldenEggs)} GE',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBoostTime(double seconds) {
    final totalSeconds = seconds.ceil();
    final minutes = totalSeconds ~/ BalanceConfig.secondsPerMinute;
    final remainingSeconds = totalSeconds % BalanceConfig.secondsPerMinute;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildTrophiesPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.emoji_events),
            title: const Text('Chicken-count trophies'),
            subtitle: Text(
              'Owned: ${_engine.state.trophies.length} · '
              'Prophecy Eggs: ${formatNumber(_engine.state.prophecyEggs)}',
            ),
          ),
        ),
        for (var eggIndex = 0; eggIndex < widget.data.eggs.length; eggIndex++)
          Card(
            child: ExpansionTile(
              title: Text(widget.data.eggs[eggIndex].name),
              subtitle: Text(
                '${_engine.state.trophies.where((id) => id.startsWith(
                      '${widget.data.eggs[eggIndex].id}:trophy:',
                    )).length}/${BalanceConfig.trophyTierNames.length} '
                'trophies earned',
              ),
              children: [
                for (var trophyIndex = 0;
                    trophyIndex < BalanceConfig.trophyTierNames.length;
                    trophyIndex++)
                  ListTile(
                    leading: Icon(
                      _engine.state.trophies.contains(
                        '${widget.data.eggs[eggIndex].id}:trophy:$trophyIndex',
                      )
                          ? Icons.emoji_events
                          : Icons.emoji_events_outlined,
                    ),
                    title: Text(
                      '${BalanceConfig.trophyTierNames[trophyIndex]} trophy',
                    ),
                    subtitle: Text(
                      'Reach ${formatNumber(_engine.trophyChickenCountThreshold(trophyIndex))} '
                      'chickens · ${_trophyRewardLabel(widget.data.eggs[eggIndex].id, trophyIndex)}',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _trophyRewardLabel(String eggId, int trophyIndex) {
    final soulEggRewards = BalanceConfig.trophySoulEggRewards[eggId];
    if (soulEggRewards != null && trophyIndex < soulEggRewards.length) {
      return '+${formatNumber(soulEggRewards[trophyIndex])} Soul Eggs';
    }
    final goldenEggRewards = BalanceConfig.trophyGoldenEggRewards[eggId];
    if (goldenEggRewards != null && trophyIndex < goldenEggRewards.length) {
      return '+${formatNumber(goldenEggRewards[trophyIndex])} Golden Eggs';
    }
    if (eggId == 'enlightenment' &&
        trophyIndex <
            BalanceConfig.enlightenmentTrophyProphecyEggRewards.length) {
      return '+${formatNumber(BalanceConfig.enlightenmentTrophyProphecyEggRewards[trophyIndex])} '
          'Prophecy Eggs';
    }
    if (trophyIndex == BalanceConfig.trophyTierNames.length - 1) {
      final prophecyReward =
          BalanceConfig.prophecyEggTrophyReward(eggId);
      return '+${formatNumber(prophecyReward)} Prophecy Eggs';
    }
    return 'Reward not listed on source page';
  }

  String _boostEffectLabel(String effect) => switch (effect) {
        'earnings' => 'earnings',
        'internalHatchery' => 'internal hatchery rate',
        'boostBeacon' => 'boost effectiveness',
        'soulEggGain' => 'Soul Egg gain',
        _ => 'temporary boost',
      };

  Widget _buildResearchTier(int tier, List<ResearchData> items) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final unlocked = _engine.isCommonResearchTierUnlocked(tier);
    final requiredLevels =
        tier - 1 < widget.data.commonResearchTierUnlocks.length
            ? widget.data.commonResearchTierUnlocks[tier - 1]
            : 0;
    final previousLevels =
        widget.data.commonResearch.where((item) => item.tier! < tier).fold<int>(
              0,
              (total, item) =>
                  total +
                  (_engine.state.commonResearchLevels[item.id] ?? 0)
                      .clamp(0, item.maxLevel),
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: BalanceConfig.researchRowSpacing,
          ),
          child: Text(
            'Tier $tier',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final item in items)
          _buildResearchItem(
            item,
            unlocked,
            requiredLevels: requiredLevels,
            previousLevels: previousLevels,
          ),
      ],
    );
  }

  Widget _buildResearchItem(
    ResearchData item,
    bool tierUnlocked, {
    required int requiredLevels,
    required int previousLevels,
  }) {
    final level = _engine.state.commonResearchLevels[item.id] ?? 0;
    final cost = _engine.commonResearchCost(item.id);
    final maxed = level >= item.maxLevel;
    final requirement = tierUnlocked
        ? null
        : 'Unlocks after $requiredLevels total research levels in earlier '
            'tiers ($previousLevels / $requiredLevels completed).';
    return _buildResearchCard(
      item: item,
      level: level,
      cost: cost,
      currency: 'cash',
      maxed: maxed,
      affordable: !maxed && _engine.state.cash >= cost,
      lockedRequirement: requirement,
      onBuy: () => _mutate(() => _engine.buyCommonResearch(item.id)),
    );
  }

  Future<void> _confirmPrestige() async {
    final gainedSoulEggs = _engine.soulEggsGained;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Prestige and start over?'),
        content: Text(
          'You will gain ${formatNumber(gainedSoulEggs)} Soul Eggs. '
          'Golden Eggs, Soul Eggs, Prophecy Eggs, epic research, and trophies '
          'will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Prestige'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _mutate(_engine.prestige);
      try {
        await _session.save();
      } catch (error) {
        _showPersistenceError(error);
      }
    }
  }

  void _mutate<T>(T Function() action) {
    action();
    _session.refresh();
  }
}
