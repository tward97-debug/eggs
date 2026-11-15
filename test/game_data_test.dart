import 'package:flutter_test/flutter_test.dart';

import 'package:egg_empire/config/balance.dart';
import 'package:egg_empire/data/game_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads and validates all Phase 1 balance data', () async {
    final data = await const GameDataLoader().load();

    expect(data.habs, hasLength(19));
    expect(data.vehicles, hasLength(12));
    expect(data.eggs, hasLength(19));
    expect(data.commonResearch, isNotEmpty);
    expect(data.epicResearch, hasLength(17));
    expect(data.commonResearchTierUnlocks, hasLength(13));
    expect(data.boosts, hasLength(4));
    expect(data.eggs.map((egg) => egg.id).toSet(), hasLength(data.eggs.length));

    final addedEggs = data.eggs.skip(9).toList();
    for (var index = 1; index < addedEggs.length; index++) {
      expect(
        addedEggs[index].valuePerEgg,
        greaterThan(addedEggs[index - 1].valuePerEgg),
      );
      expect(
        addedEggs[index].upgradeFarmValue,
        greaterThan(addedEggs[index - 1].upgradeFarmValue!),
      );
    }

    expect(data.habs.first.slotPrices, hasLength(4));
    expect(data.habs.last.maxCapacityMultiplier, 4.725);
    expect(data.vehicles.first.capacityPerMinute, 5000);
    expect(data.vehicles.last.firstPrice, 21.124e36);
    expect(data.eggs.first.upgradeFarmValue, 0);
    expect(data.eggs[6].upgradeFarmValue, isNull);
    expect(BalanceConfig.placeholderEggUpgradeFarmValues['quantum'], 4e19);
    expect(data.commonResearch.first.mode, isNotNull);
    expect(data.epicResearch.first.mode, isNull);
    expect(BalanceConfig.vehiclePriceCurveA, hasLength(13));
    expect(BalanceConfig.vehiclePriceCurveB, hasLength(14));
  });
}
