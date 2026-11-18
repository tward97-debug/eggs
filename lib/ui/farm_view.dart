import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/balance.dart';
import '../game/engine.dart';

/// The home screen: HUD on top, the farm in the middle, hatch button below.
class FarmView extends StatelessWidget {
  const FarmView({
    super.key,
    required this.engine,
    required this.formatNumber,
    required this.droneVisible,
    required this.droneWarning,
    required this.dronePosition,
    required this.onCollectDrone,
    required this.onHatchStart,
    required this.onHatchStop,
    required this.onAscend,
    required this.onOpenHabitats,
    required this.onOpenTransport,
    required this.onOpenSilos,
    required this.onOpenPage,
    required this.menuPages,
  });

  final GameEngine engine;
  final String Function(double) formatNumber;

  /// The drone hovers in one spot for its short visible window.
  final bool droneVisible;

  /// A red dot marks the spot shortly before the drone appears.
  final bool droneWarning;

  /// Where in the scene the dot and then the drone show.
  final Alignment dronePosition;
  final VoidCallback onCollectDrone;
  final VoidCallback onHatchStart;
  final VoidCallback onHatchStop;
  final VoidCallback onAscend;
  final VoidCallback onOpenHabitats;
  final VoidCallback onOpenTransport;
  final VoidCallback onOpenSilos;
  final void Function(int page) onOpenPage;

  /// Page index, label and icon for every non-farm page, in menu order.
  final List<(int, String, IconData)> menuPages;

  static const _sky = Color(0xFF8FD3F4);
  static const _grass = Color(0xFF6DBE45);
  static const _hatchRed = Color(0xFFD9382C);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildHud(theme),
        if (engine.canAscend)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('ascend-button'),
                onPressed: onAscend,
                icon: const Icon(Icons.arrow_upward),
                label: Text(
                  'Upgrade to ${engine.data.eggs[engine.eggIndex + 1].name} '
                  'eggs',
                ),
              ),
            ),
          ),
        Expanded(child: _buildScene(theme)),
        _buildBars(theme),
        _buildControls(theme),
      ],
    );
  }

  Widget _buildHud(ThemeData theme) {
    final threshold = engine.nextEggUpgradeFarmValue;
    // Wiki ring formula: angle = 360 * P^log10(2), so each 10x of farm value
    // roughly doubles the visible arc.
    final ring = threshold == null
        ? 1.0
        : math
            .pow((engine.farmValue / threshold).clamp(0.0, 1.0), 0.30103)
            .toDouble();
    return Padding(
      key: const ValueKey('farm-cash-panel'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: ring,
                    strokeWidth: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    semanticsLabel: 'Farm value progress',
                  ),
                ),
                Icon(Icons.egg, size: 34, color: theme.colorScheme.primary),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '\$${formatNumber(engine.state.cash)}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '\$${formatNumber(engine.cashPerSecond)}/sec · '
                  '${engine.currentEgg.name} egg',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  threshold == null
                      ? 'Farm value ${formatNumber(engine.farmValue)}'
                      : 'Farm value ${formatNumber(engine.farmValue)} / '
                          '${formatNumber(threshold)}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _currency(
                Icons.egg_alt,
                Colors.amber.shade700,
                formatNumber(engine.state.goldenEggs),
                'Golden Eggs',
              ),
              _currency(
                Icons.auto_awesome,
                Colors.purple,
                formatNumber(engine.state.soulEggs),
                'Soul Eggs',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _currency(IconData icon, Color color, String amount, String label) {
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(amount),
        ],
      ),
    );
  }

  Widget _buildScene(ThemeData theme) {
    final runningBonus = engine.runningChickenMultiplier;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_sky, _sky, _grass, _grass],
          stops: [0, 0.4, 0.4, 1],
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(0, -0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var slot = 0; slot < BalanceConfig.maximumHabCount; slot++)
                  Expanded(child: _habSlot(theme, slot)),
              ],
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.75),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                for (final _ in engine.state.vehicles)
                  const Icon(Icons.local_shipping, color: Colors.white),
              ],
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: ActionChip(
              key: const ValueKey('open-silos'),
              avatar: const Icon(Icons.warehouse_outlined, size: 18),
              label: Text(
                '${engine.state.siloCount} silo'
                '${engine.state.siloCount == 1 ? '' : 's'} · '
                '${(engine.state.siloCount * engine.siloMinutes).round()} '
                'min',
              ),
              onPressed: onOpenSilos,
            ),
          ),
          if (runningBonus > 1)
            Positioned(
              right: 8,
              top: 8,
              child: Chip(
                avatar: const Icon(Icons.directions_run, size: 18),
                label: Text('×${formatNumber(runningBonus)}'),
              ),
            ),
          if (droneVisible || droneWarning)
            Align(
              alignment: dronePosition,
              child: SizedBox(
                width: BalanceConfig.droneButtonDiameter,
                height: BalanceConfig.droneButtonDiameter,
                child: droneVisible
                    ? FilledButton(
                        key: const ValueKey('drone-button'),
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onCollectDrone,
                        child: const Icon(
                          Icons.flight,
                          semanticLabel: 'Drone',
                        ),
                      )
                    : const Center(
                        child: SizedBox(
                          key: ValueKey('drone-warning'),
                          width: BalanceConfig.droneWarningDotDiameter,
                          height: BalanceConfig.droneWarningDotDiameter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _habSlot(ThemeData theme, int slot) {
    final owned = engine.state.habs
        .where((hab) => hab.slotIndex == slot)
        .map((hab) => engine.data.habs[hab.tierIndex])
        .firstOrNull;
    return InkWell(
      onTap: onOpenHabitats,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              owned == null ? Icons.add_home_outlined : Icons.house,
              size: 44,
              color: owned == null ? Colors.white70 : Colors.brown.shade700,
            ),
            SizedBox(
              width: double.infinity,
              child: Text(
                owned?.name ?? 'Empty lot',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBars(ThemeData theme) {
    final capacity = engine.totalHabCapacity;
    final shipping = engine.shipCapacityPerMinute;
    final backingUp = engine.eggsBackingUp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _bar(
              theme,
              key: const ValueKey('open-habitats'),
              icon: Icons.home_work_outlined,
              label: 'Chickens ${formatNumber(engine.state.chickens)} / '
                  '${formatNumber(capacity)}',
              value: capacity <= 0 ? 0 : engine.state.chickens / capacity,
              color: theme.colorScheme.primary,
              onTap: onOpenHabitats,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _bar(
              theme,
              key: const ValueKey('open-transport'),
              icon: Icons.local_shipping_outlined,
              label: backingUp
                  ? 'Eggs backing up!'
                  : 'Shipping ${formatNumber(engine.eggsLaidPerMinute)} / '
                      '${formatNumber(shipping)}',
              value: shipping <= 0 ? 0 : engine.eggsLaidPerMinute / shipping,
              color: backingUp
                  ? theme.colorScheme.error
                  : theme.colorScheme.tertiary,
              onTap: onOpenTransport,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(
    ThemeData theme, {
    required Key key,
    required IconData icon,
    required String label,
    required double value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                color: color,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    final stock = engine.state.hatcheryStock;
    final capacity = engine.hatcheryCapacity;
    final primary = menuPages.take(3).toList();
    final overflow = menuPages.skip(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _menuButton(theme, primary[0])),
          Expanded(child: _menuButton(theme, primary[1])),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Listener(
                onPointerDown: (_) => onHatchStart(),
                onPointerUp: (_) => onHatchStop(),
                onPointerCancel: (_) => onHatchStop(),
                child: Semantics(
                  button: true,
                  label: 'Hatch chickens. Tap or hold.',
                  child: SizedBox(
                    key: const ValueKey('hatch-button'),
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: capacity <= 0
                                ? 0
                                : (stock / capacity).clamp(0.0, 1.0),
                            strokeWidth: 6,
                            color: Colors.amber,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            semanticsLabel: 'Hatchery stock',
                          ),
                        ),
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: stock > 0 ? _hatchRed : Colors.grey,
                            boxShadow: const [
                              BoxShadow(
                                blurRadius: 6,
                                offset: Offset(0, 3),
                                color: Colors.black26,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.egg_alt,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatNumber(stock)} / ${formatNumber(capacity)}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          Expanded(child: _menuButton(theme, primary[2])),
          Expanded(
            child: PopupMenuButton<int>(
              tooltip: 'More',
              onSelected: onOpenPage,
              itemBuilder: (context) => [
                for (final (page, label, icon) in overflow)
                  PopupMenuItem(
                    value: page,
                    child: ListTile(
                      leading: Icon(icon),
                      title: Text(label),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
              child: _menuLabel(theme, Icons.menu, 'More'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuButton(ThemeData theme, (int, String, IconData) entry) {
    final (page, label, icon) = entry;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpenPage(page),
      child: _menuLabel(theme, icon, label),
    );
  }

  Widget _menuLabel(ThemeData theme, IconData icon, String label) {
    return SizedBox(
      height: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
