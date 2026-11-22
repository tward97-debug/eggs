import 'dart:convert';

import 'package:egg_empire/config/balance.dart';
import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/ui/game_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A save exactly as version 0.1.5 wrote it. Do not update this when the save
/// format grows: the point is that an update must still load it. New fields
/// have to be optional.
const _save015 = {
  'version': 2,
  'lastSavedAt': '2026-11-20T12:00:00.000Z',
  'state': {
    'cash': 12345.5,
    'cashEarnedThisPrestige': 9e9,
    'cashEarnedThisRun': 5e6,
    'cashSpentThisRun': 4e6,
    'chickens': 321.0,
    'hatcheryStock': 100.0,
    'goldenEggs': 77.5,
    'piggyBankGoldenEggs': 900.0,
    'soulEggs': 42.3,
    'eggIndex': 2,
    'siloCount': 2,
    'hapticsEnabled': true,
    'habs': [
      {'tierIndex': 3, 'slotIndex': 0},
      {'tierIndex': 1, 'slotIndex': 2},
    ],
    'vehicles': [
      {'tierIndex': 0, 'unitNumber': 1, 'slotIndex': 0},
      {'tierIndex': 2, 'unitNumber': 1, 'slotIndex': 1},
    ],
    'commonResearchLevels': {'comfy_nests': 5},
    'epicResearchLevels': {'soul_food': 2},
    'activeBoostSeconds': {'best_bird_feed': 500.0},
    'activeBoostMultipliers': {'best_bird_feed': 3.0},
    'trophies': ['edible:trophy:0'],
    'garden': {
      'extraPlots': 2,
      'lastSeenMs': 1795000000000,
      'planted': {
        '0': {'cropId': 'corn', 'plantedAtMs': 1794990000000},
        '9': {'cropId': 'soul_root', 'plantedAtMs': 1794990000000},
      },
      'lastCrops': {'0': 'corn', '9': 'soul_root'},
      'harvested': {'corn': 40, 'crazy_corn': 3},
      'boosts': {'tachyon_prism': 1},
      'unlockRewardsPaid': ['crazy_corn'],
    },
    'runningChickenBatches': <Object>[],
  },
};

void main() {
  test('updating keeps a 0.1.5 save: nothing is wiped or reset', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await const GameDataLoader().load();
    SharedPreferences.setMockInitialValues({
      BalanceConfig.savePreferenceKey: jsonEncode(_save015),
    });

    // Restored one second after the save, so offline progress is negligible.
    final session = await GameSession.restore(
      data,
      now: DateTime.utc(2026, 11, 20, 12, 0, 1),
    );
    final state = session.engine.state;

    expect(session.oldSaveWasReset, isFalse);
    expect(state.soulEggs, 42.3);
    expect(state.goldenEggs, 77.5);
    expect(state.piggyBankGoldenEggs, 900);
    expect(state.eggIndex, 2);
    expect(state.cash, greaterThanOrEqualTo(12345.5));
    expect(state.habs, hasLength(2));
    expect(state.vehicles, hasLength(2));
    expect(state.commonResearchLevels['comfy_nests'], 5);
    expect(state.epicResearchLevels['soul_food'], 2);
    expect(state.activeBoostSeconds['best_bird_feed'], closeTo(499, 1));
    expect(state.trophies, contains('edible:trophy:0'));
    expect(state.garden.extraPlots, 2);
    expect(state.garden.planted[9]!.cropId, 'soul_root');
    expect(state.garden.harvested['corn'], 40);
    expect(state.garden.boosts['tachyon_prism'], 1);
    expect(state.garden.unlockRewardsPaid, {'crazy_corn'});
    await session.close();
  });
}
