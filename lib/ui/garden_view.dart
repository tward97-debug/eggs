import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/engine.dart';
import '../game/models/game_data.dart';

/// The Garden page: a grid of plots that grow crops in real time.
class GardenView extends StatelessWidget {
  const GardenView({
    super.key,
    required this.engine,
    required this.formatNumber,
    required this.nowMs,
    required this.onChanged,
  });

  final GameEngine engine;
  final String Function(double value) formatNumber;

  /// Garden time from [Garden.gardenNow].
  final int nowMs;

  /// Called after any garden action; `planted` is true when a crop went in.
  final void Function({bool planted}) onChanged;

  @override
  Widget build(BuildContext context) {
    final statuses = [
      for (var plot = 0; plot < engine.gardenPlotCount; plot++)
        engine.plotStatus(plot, nowMs),
    ];
    final canCollect = statuses.any(
      (status) => status == PlotStatus.ready || status == PlotStatus.withered,
    );
    final canReplant = [
      for (var plot = 0; plot < statuses.length; plot++)
        statuses[plot] == PlotStatus.empty &&
            engine.state.garden.lastCrops.containsKey(plot),
    ].contains(true);
    final plotPrice = engine.nextPlotPrice;
    final bonus = math
        .pow(engine.prophecyEggMultiplier, engine.gardenBonusUnits)
        .toDouble();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.grass),
            title: Text('Garden bonus ×${formatNumber(bonus)}'),
            subtitle: Text(
              'Permanent boost to your Soul Egg bonus from Candy Corn. '
              'Seeds cost \$${formatNumber(engine.seedCost)} each. Ripe crops '
              'wither after ${engine.data.garden.witherMinutes.round()} '
              'minutes.',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('garden-harvest-all'),
                onPressed: canCollect
                    ? () {
                        engine.harvestAll(nowMs);
                        onChanged();
                      }
                    : null,
                child: const Text('Harvest all'),
              ),
              FilledButton.tonal(
                key: const ValueKey('garden-replant'),
                onPressed: canReplant && engine.state.cash >= engine.seedCost
                    ? () {
                        engine.replantAll(nowMs);
                        onChanged(planted: true);
                      }
                    : null,
                child: const Text('Replant same'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('garden-goals'),
                onPressed: () => _showGoals(context),
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Goals'),
              ),
              OutlinedButton(
                key: const ValueKey('garden-buy-plot'),
                onPressed: engine.state.goldenEggs >= plotPrice
                    ? () {
                        engine.buyPlot();
                        onChanged();
                      }
                    : null,
                child: Text(
                  plotPrice.isFinite
                      ? 'Buy plot · ${formatNumber(plotPrice)} GE'
                      : 'All plots owned',
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.7,
          children: [
            for (var plot = 0; plot < statuses.length; plot++)
              _buildPlot(context, plot, statuses[plot]),
          ],
        ),
      ],
    );
  }

  Widget _buildPlot(BuildContext context, int plot, PlotStatus status) {
    final planted = engine.state.garden.planted[plot];
    final name = planted == null ? 'Empty' : engine.crop(planted.cropId).name;
    final colors = Theme.of(context).colorScheme;
    final (icon, detail, color, onTap) = switch (status) {
      PlotStatus.empty => (
          Icons.add,
          'Tap to plant',
          null,
          () => _showCropPicker(context, plot),
        ),
      PlotStatus.growing => (
          Icons.eco_outlined,
          _formatDuration(engine.cropReadyAtMs(planted!) - nowMs),
          null,
          null,
        ),
      PlotStatus.ready => (
          Icons.agriculture,
          'Ready · ${_formatDuration(engine.cropWitherAtMs(planted!) - nowMs)}',
          colors.primaryContainer,
          () {
            engine.harvestPlot(plot, nowMs);
            onChanged();
          },
        ),
      PlotStatus.withered => (
          Icons.delete_outline,
          'Withered',
          colors.errorContainer,
          () {
            engine.clearPlot(plot, nowMs);
            onChanged();
          },
        ),
    };
    return Card(
      key: ValueKey('garden-plot-$plot'),
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              Flexible(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Flexible(
                child: Text(
                  detail,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Progress toward each harvest count that unlocks the next crop.
  Future<void> _showGoals(BuildContext context) {
    final paid = engine.state.garden.unlockRewardsPaid;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Garden goals'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final next in engine.data.garden.crops)
                if (next.unlockCropId case final cropId?)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      engine.isCropUnlocked(next)
                          ? Icons.emoji_events
                          : Icons.emoji_events_outlined,
                    ),
                    title: Text(
                      'Harvest ${next.unlockHarvests} ${engine.crop(cropId).name}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: (engine.cropHarvested(cropId) /
                                  next.unlockHarvests)
                              .clamp(0.0, 1.0),
                        ),
                        Text(
                          '${math.min(engine.cropHarvested(cropId), next.unlockHarvests)} / '
                          '${next.unlockHarvests} · unlocks ${next.name}'
                          '${paid.contains(next.id) ? ' · reward claimed' : next.unlockRewardSoulEggPercent > 0 ? ' · reward +${formatNumber(next.unlockRewardSoulEggPercent)}% Soul Eggs' : ''}',
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCropPicker(BuildContext context, int plot) {
    final cost = engine.seedCost;
    final affordable = engine.state.cash >= cost;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('Choose a crop'),
            subtitle: Text(
              affordable
                  ? 'Seed cost: \$${formatNumber(cost)}'
                  : 'Seed cost: \$${formatNumber(cost)} · not enough cash',
            ),
          ),
          for (final crop in engine.data.garden.crops)
            _buildCropOption(sheetContext, plot, crop, affordable),
        ],
      ),
    );
  }

  Widget _buildCropOption(
    BuildContext sheetContext,
    int plot,
    CropData crop,
    bool affordable,
  ) {
    final unlocked = engine.isCropUnlocked(crop);
    final unlockCrop = crop.unlockCropId;
    return ListTile(
      enabled: unlocked,
      leading: Icon(unlocked ? Icons.eco : Icons.lock_outline),
      title: Text(crop.name),
      subtitle: Text(
        unlocked
            ? '${formatNumber(crop.growHours)} h · ${_rewardLabel(crop)}'
            : 'Locked · ${engine.cropHarvested(unlockCrop!)} / '
                '${crop.unlockHarvests} ${engine.crop(unlockCrop).name} '
                'harvested'
                '${crop.unlockRewardSoulEggPercent > 0 ? ' · reward +${formatNumber(crop.unlockRewardSoulEggPercent)}% Soul Eggs' : ''}',
      ),
      trailing: unlocked
          ? FilledButton(
              key: ValueKey('plant-${crop.id}'),
              onPressed: affordable
                  ? () {
                      engine.plantCrop(plot, crop.id, nowMs);
                      Navigator.of(sheetContext).pop();
                      onChanged(planted: true);
                    }
                  : null,
              child: const Text('Plant'),
            )
          : null,
    );
  }

  String _rewardLabel(CropData crop) {
    switch (crop.reward) {
      case 'soulEggs':
        return '+${formatNumber(crop.amount)} Soul Eggs';
      case 'earningsBonus':
        final percent =
            (math.pow(engine.prophecyEggMultiplier, crop.amount) - 1) * 100;
        return '+${percent.toStringAsFixed(2)}% garden bonus, forever';
      default:
        final boost =
            engine.data.boosts.firstWhere((boost) => boost.id == crop.boostId);
        final option = boost.options.firstWhere((option) => option.gardenOnly);
        return '${boost.name} ${option.label}';
    }
  }

  static String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).ceil();
    final hours = seconds ~/ 3600;
    final minutes = seconds % 3600 ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m ${seconds % 60}s';
  }
}
