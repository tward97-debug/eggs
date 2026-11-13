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
import 'game_session.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.data});

  final GameData? data;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Future<GameData> _gameData = const GameDataLoader().load();

  @override
  Widget build(BuildContext context) {
    final suppliedData = widget.data;
    if (suppliedData != null) {
      return _LoadedGameScreen(data: suppliedData);
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
        return _LoadedGameScreen(data: data);
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
  const _LoadedGameScreen({required this.data});

  final GameData data;

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
        return _RunningGameScreen(data: widget.data, session: session);
      },
    );
  }
}

class _RunningGameScreen extends StatefulWidget {
  const _RunningGameScreen({
    required this.data,
    required this.session,
  });

  final GameData data;
  final GameSession session;

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
  int _lastHapticMilliseconds =
      -BalanceConfig.hapticFeedbackThrottleMilliseconds;
  int _selectedPage = 0;
  bool _scientificNumberFormat = false;
  bool _showOfflineSummary = BalanceConfig.showOfflineSummaryDefault;
  int _droneRewardEffectSequence = 0;
  String? _droneRewardMessage;
  bool _droneRewardIsGoldenEgg = false;
  final math.Random _droneRandom = math.Random();
  double _droneSecondsUntilSpawn = BalanceConfig.droneSpawnIntervalSec;
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
      _session.close().catchError((Object error, StackTrace stackTrace) {
        _showPersistenceError(error);
      }),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastElapsedMilliseconds = _stopwatch.elapsedMilliseconds;
      unawaited(_resumeGame());
    } else {
      _gameTimer?.cancel();
      _gameTimer = null;
      _droneFlightDuration = 0;
      _droneFlightElapsed = 0;
      _droneSecondsUntilSpawn = BalanceConfig.droneSpawnIntervalSec;
      unawaited(_pauseAndSave());
    }
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
    final deltaMilliseconds = elapsedMilliseconds - _lastElapsedMilliseconds;
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
      _buildTransportPage(),
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
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Transport',
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
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
        ),
        _buildDroneCard(),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Haptic feedback'),
                  value: _engine.state.hapticsEnabled,
                  onChanged: _session.setHapticsEnabled,
                ),
                Text(
                  'Internal hatcheries: '
                  '${formatNumber(_engine.flatResearchBonus('ihrPerHab'))} '
                  'chickens/min per habitat',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Habitats', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: List<Widget>.generate(
            BalanceConfig.maximumHabCount,
            _buildHabSlot,
          ),
        ),
      ],
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

  Widget _buildHabSlot(int slotIndex) {
    final hab = _engine.state.habs
        .where((item) => item.slotIndex == slotIndex)
        .firstOrNull;
    final theme = Theme.of(context);
    final price = _engine.habPrice(0, slotIndex: slotIndex);
    final canAfford = _engine.state.cash >= price;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openHabitatSlot(slotIndex),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hab == null ? Icons.add_home_work_outlined : Icons.home_work,
                size: 30,
              ),
              const SizedBox(height: 6),
              Text(
                'Habitat ${slotIndex + 1}',
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              if (hab == null) ...[
                const Text('Empty'),
                Text(
                  price.isFinite
                      ? 'Build · ${formatNumber(price)}'
                      : 'Unavailable',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: canAfford ? null : theme.colorScheme.error,
                  ),
                ),
              ] else ...[
                Text(
                  'Tier ${hab.tierIndex + 1}',
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${formatNumber(_engine.capacityForHab(hab.tierIndex))} '
                  'capacity',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                if (hab.tierIndex + 1 < widget.data.habs.length)
                  Text('Tap to upgrade', style: theme.textTheme.bodySmall)
                else
                  Text('Max tier', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openHabitatSlot(int slotIndex) async {
    final hab = _engine.state.habs
        .where((item) => item.slotIndex == slotIndex)
        .firstOrNull;
    if (hab == null) {
      final price = _engine.habPrice(0, slotIndex: slotIndex);
      if (_engine.state.cash >= price && price.isFinite) {
        _mutate(
          () => _engine.buyHab(0, slotIndex: slotIndex),
        );
      }
      return;
    }

    final targetTier = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Habitat ${slotIndex + 1} · Tier ${hab.tierIndex + 1}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var tier = hab.tierIndex + 1;
                    tier < widget.data.habs.length;
                    tier++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: _engine.state.cash >=
                              widget.data.habs[tier].slotPrices[slotIndex]
                          ? () => Navigator.of(context).pop(tier)
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Upgrade to Tier ${tier + 1} · '
                            '${widget.data.habs[tier].name}',
                          ),
                          Text(
                            'Capacity: '
                            '${formatNumber(_engine.capacityForHab(tier))} '
                            'chickens · '
                            '${formatNumber(widget.data.habs[tier].slotPrices[slotIndex])}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (targetTier != null && mounted) {
      _mutate(
        () => _engine.upgradeHab(
          hab.tierIndex,
          slotIndex,
          targetTierIndex: targetTier,
        ),
      );
    }
  }

  Widget _buildTransportPage() {
    return Column(
      children: [
        _buildCashBalanceHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Card(
                child: ListTile(
                  title: const Text('Shipping capacity'),
                  subtitle: Text(
                    '${formatNumber(_engine.shipCapacityPerMinute)} eggs/min'
                    ' · ${_engine.state.vehicles.length}/'
                    '${formatNumber(_engine.maximumFleetSize)} slots',
                  ),
                  leading: const Icon(Icons.local_shipping),
                ),
              ),
              const SizedBox(height: 8),
              Text('Vehicles', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.15,
                children: List<Widget>.generate(
                  _engine.maximumFleetSize.floor(),
                  _buildVehicleSlot,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCashBalanceHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        key: const ValueKey('cash-balance-header'),
        child: ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Farm cash'),
          trailing: Text(
            formatNumber(_engine.state.cash),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleSlot(int slotIndex) {
    final vehicle = _engine.state.vehicles
        .where((item) => item.slotIndex == slotIndex)
        .firstOrNull;
    final isUnlocked = slotIndex < _engine.maximumFleetSize;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: isUnlocked ? null : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: isUnlocked ? () => _openVehicleSlot(slotIndex) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                vehicle == null
                    ? Icons.add_road_outlined
                    : Icons.local_shipping,
                size: 30,
              ),
              const SizedBox(height: 6),
              Text(
                'Vehicle ${slotIndex + 1}',
                style: theme.textTheme.titleSmall,
              ),
              if (!isUnlocked)
                Text(
                  'Locked · fleet research',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else if (vehicle == null)
                Text(
                  'Empty · tap to buy',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else ...[
                Text(
                  widget.data.vehicles[vehicle.tierIndex].name,
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${formatNumber(_engine.capacityForVehicle(vehicle.tierIndex))} '
                  'eggs/min',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  vehicle.tierIndex + 1 < widget.data.vehicles.length
                      ? 'Tap to upgrade'
                      : 'Max tier',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openVehicleSlot(int slotIndex) async {
    final vehicle = _engine.state.vehicles
        .where((item) => item.slotIndex == slotIndex)
        .firstOrNull;
    final firstTier = vehicle?.tierIndex ?? -1;
    final choices = <Widget>[];
    for (var tier = firstTier + 1; tier < widget.data.vehicles.length; tier++) {
      final item = widget.data.vehicles[tier];
      final price = _engine.vehicleUpgradePrice(tier);
      final freeTierAlreadyOwned = item.firstPrice == 0 &&
          _engine.state.vehicles.any((owned) => owned.tierIndex == tier);
      choices.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            onPressed: _engine.state.cash >= price && !freeTierAlreadyOwned
                ? () => Navigator.of(context).pop(tier)
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vehicle == null
                      ? 'Buy ${item.name}'
                      : 'Upgrade to ${item.name}',
                ),
                Text(
                  '${formatNumber(_engine.capacityForVehicle(tier))} eggs/min · '
                  '${price == 0 && !freeTierAlreadyOwned ? 'Free' : '${formatNumber(price)} cash'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final targetTier = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Vehicle ${slotIndex + 1}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: choices.isEmpty
                  ? [const Text('This vehicle is already at the highest tier.')]
                  : choices,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (targetTier == null || !mounted) {
      return;
    }
    if (vehicle == null) {
      _mutate(
        () => _engine.buyVehicle(targetTier, slotIndex: slotIndex),
      );
    } else {
      _mutate(
        () => _engine.upgradeVehicle(
          slotIndex,
          targetTierIndex: targetTier,
        ),
      );
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
                  subtitle: Text(
                    'Invest farm cash to improve production, housing, and transport.',
                  ),
                ),
              ),
              for (final tier in tiers)
                _buildResearchTier(
                  tier,
                  items.where((item) => item.tier == tier).toList(
                        growable: false,
                      ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Epic research'),
                  subtitle: Text(
                    'Permanent upgrades · '
                    '${formatNumber(_engine.state.goldenEggs)} Golden Eggs',
                  ),
                ),
              ),
              for (final item in widget.data.epicResearch)
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
    final canBuy = !maxed && _engine.state.goldenEggs >= cost;
    return Card(
      child: ListTile(
        title: Text(item.name),
        subtitle: Text(
          '${_effectLabel(item.effect)} · '
          '+${formatNumber(item.perLevel)} per level · '
          'level $level/${item.maxLevel}',
        ),
        trailing: TextButton(
          onPressed: canBuy
              ? () => _mutate(() => _engine.buyEpicResearch(item.id))
              : null,
          child: Text(maxed ? 'MAX' : '${formatNumber(cost)} GE'),
        ),
      ),
    );
  }

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
                  : '${_effectLabel(boost.effect)} · '
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

  Widget _buildDroneCard() {
    if (!_hasActiveDrone) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: Material(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _collectDrone,
                  child: const Center(
                    child: Text(
                      'TAP ANYWHERE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            LinearProgressIndicator(value: 1 - _droneFlightProgress),
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
    if (trophyIndex == BalanceConfig.trophyTierNames.length - 1) {
      final prophecyReward = BalanceConfig.trophyProphecyEggRewards[eggId];
      if (prophecyReward != null) {
        return '+${formatNumber(prophecyReward)} Prophecy Eggs';
      }
    }
    if (eggId == 'enlightenment' &&
        trophyIndex <
            BalanceConfig.enlightenmentTrophyProphecyEggRewards.length) {
      return '+${formatNumber(BalanceConfig.enlightenmentTrophyProphecyEggRewards[trophyIndex])} '
          'Prophecy Eggs';
    }
    return 'Reward not listed on source page';
  }

  Widget _buildResearchTier(int tier, List<ResearchData> items) {
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
    return Card(
      child: ExpansionTile(
        initiallyExpanded: tier == 1,
        title: Text('Research group $tier'),
        subtitle: Text(
          unlocked
              ? '${items.length} upgrades available'
              : '$previousLevels / $requiredLevels earlier upgrades needed',
        ),
        children: [
          if (!unlocked)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Complete upgrades in previous groups to unlock.'),
            ),
          for (var index = 0; index < items.length; index++)
            _buildResearchItem(index, items[index], unlocked),
        ],
      ),
    );
  }

  Widget _buildResearchItem(
      int itemIndex, ResearchData item, bool tierUnlocked) {
    final level = _engine.state.commonResearchLevels[item.id] ?? 0;
    final cost = _engine.commonResearchCost(item.id);
    final maxed = level >= item.maxLevel;
    final canBuy = tierUnlocked && !maxed && _engine.state.cash >= cost;
    return ListTile(
      title: Text('Upgrade ${itemIndex + 1}'),
      subtitle: Text(
        '${_effectLabel(item.effect)} · ${_researchBenefit(item)}'
        ' · level $level/${item.maxLevel}',
      ),
      trailing: TextButton(
        onPressed: canBuy
            ? () => _mutate(() => _engine.buyCommonResearch(item.id))
            : null,
        child: Text(maxed ? 'MAX' : formatNumber(cost)),
      ),
    );
  }

  String _effectLabel(String effect) {
    const labels = <String, String>{
      'layRate': 'egg laying',
      'eggValue': 'egg value',
      'hatcheryRefill': 'hatchery refill',
      'runningBonusPerChicken': 'flock bonus',
      'habCapacity': 'habitat capacity',
      'ihrPerHab': 'internal hatcheries',
      'hatcheryCapacity': 'hatchery stock',
      'vehicleCapacity': 'vehicle capacity',
      'fleetSize': 'vehicle slots',
      'maxRunningBonus': 'flock bonus cap',
      'vehicleSpeed': 'vehicle speed',
      'hoverVehicleCapacity': 'advanced vehicle capacity',
      'portalHabCapacity': 'advanced habitat capacity',
      'hyperloopVehicleCapacity': 'train capacity',
      'soulFood': 'earnings per Soul Egg',
      'prestigeBonus': 'Soul Egg gain',
      'prophecyBonus': 'Prophecy Egg earnings bonus',
      'farmValueMult': 'farm value',
      'holdHatchPerSec': 'hold-to-hatch speed',
    };
    return effect.split('+').map((part) => labels[part] ?? part).join(' and ');
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

  String _researchBenefit(ResearchData item) {
    if (item.mode == 'add') {
      return '+${(item.perLevel * 100).toStringAsFixed(0)}% per level';
    }
    if (item.mode == 'mul') {
      return '×${formatNumber(item.perLevel)} per level';
    }
    return '+${formatNumber(item.perLevel)} per level';
  }

  void _mutate<T>(T Function() action) {
    action();
    _session.refresh();
  }
}
