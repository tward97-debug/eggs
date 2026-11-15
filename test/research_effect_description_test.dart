import 'package:flutter_test/flutter_test.dart';

import 'package:egg_empire/data/game_data.dart';
import 'package:egg_empire/game/format_number.dart';
import 'package:egg_empire/ui/research_effect_description.dart';

void main() {
  late GameData data;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    data = await const GameDataLoader().load();
  });

  test('describes every common and epic effect without exposing raw keys', () {
    final allResearch = [...data.commonResearch, ...data.epicResearch];
    final effectKeys =
        allResearch.expand((item) => item.effect.split('+')).toSet();

    for (final item in allResearch) {
      final description = describeEffect(
        item,
        1,
        formatNumber: formatNumber,
      );
      final readableText = description.readableText;
      expect(description.category, isNotEmpty, reason: item.id);
      expect(description.perLevel, isNotEmpty, reason: item.id);
      expect(description.currentTotal, contains('Now:'), reason: item.id);
      for (final effectKey in effectKeys) {
        expect(
          readableText,
          isNot(contains(effectKey)),
          reason: '${item.id} exposes raw effect "$effectKey"',
        );
      }
    }
  });
}
