/// Balance values marked as tunable or placeholders in the project spec.
class BalanceConfig {
  BalanceConfig._();

  static const int baseFleetSize = 4;
  static const int maximumFleetSlotCount = 17;
  static const double gameTicksPerSecond = 10;
  static const int gameUiRefreshMilliseconds = 100;
  static const int millisecondsPerSecond = 1000;
  static const int secondsPerMinute = 60;
  static const int microsecondsPerSecond = 1000000;
  static const double fractionalChickenEpsilon = 0.000000001;
  static const int maximumHabCount = 4;
  static const double baseEggsPerChickenPerMinute = 2;
  static const double baseHatcheryCapacity = 250;
  // TODO: verify against wiki; hatchery refill is a placeholder.
  static const double hatcheryRefillPerMin = 360;
  // TODO: verify against wiki; hold-to-hatch base speed is a placeholder.
  static const double baseHoldHatchPerSec = 10;
  static const double hatchTapBatchSize = 6;
  static const bool hapticFeedbackDefaultEnabled = true;
  static const int hapticFeedbackThrottleMilliseconds = 100;
  static const double hatcheryProgressMinimum = 0;
  static const double hatcheryProgressMaximum = 1;
  // TODO: verify against wiki; silo count and base away time are placeholders.
  static const int initialSiloCount = 1;
  static const double siloBaseMinutes = 60;
  static const int siloEpicMinutesPerLevel = 6;
  static const int offlineProgressChunkSeconds = 60;
  static const int offlineProgressMaxChunkSteps = 600;
  static const int offlineWelcomeBackThresholdSeconds = 30;
  static const int autosaveIntervalSeconds = 15;
  static const int saveFormatVersion = 1;
  static const String savePreferenceKey = 'egg_empire_save';
  static const double baseResearchMultiplier = 1;
  static const int lateCommonResearchCostTier = 6;
  static const double lateCommonResearchCostMultiplier = 10;
  static const double highImpactEggResearchMinCostGrowthPerLevel = 5;
  /// PLACEHOLDER running-chicken window and base bonus values.
  static const double runningChickenDurationSeconds = 15;
  static const double runningChickenBonusPerChicken = 0.005;
  static const double baseMaximumRunningChickenBonus = 5;
  static const bool piggyBankEnabled = true;
  static const double piggyBankResearchReward = 3;
  static const double piggyBankVehicleReward = 20;
  static const double piggyBankHabReward = 25;
  static const double piggyBankBoostReward = 25;
  static const String numberFormatPreferenceKey = 'number_format_scientific';
  static const String offlineSummaryPreferenceKey = 'show_offline_summary';
  static const bool showOfflineSummaryDefault = true;
  static const int firstResearchTier = 1;
  static const int firstPortalHabTierIndex = 17;
  static const double maxBaseHabCapacityMultiplier = 3.15;

  // TODO: verify against wiki; normalized unit-price curves are tunable.
  static const List<double> vehiclePriceCurveA = [
    1,
    2.548,
    5.147,
    9.26,
    15.71,
    25.26,
    39.16,
    58.8,
    86.2,
    123.2,
    172.8,
    238.7,
    312,
  ];

  // TODO: verify against wiki; normalized unit-price curves are tunable.
  static const List<double> vehiclePriceCurveB = [
    1,
    1.376,
    1.855,
    2.458,
    3.209,
    4.127,
    5.242,
    6.582,
    8.174,
    10.06,
    12.26,
    14.83,
    17.8,
    21.22,
  ];

  // TODO: verify against wiki; this extrapolation rate is a placeholder.
  static const double vehiclePriceExtrapolationMultiplier = 1.2;

  static const double goldenEggCostScale = 0.01;

  // TODO: verify against wiki; the Quantum threshold is explicitly a placeholder.
  static const Map<String, double> placeholderEggUpgradeFarmValues = {
    'quantum': 4e19,
  };

  /// PLACEHOLDER: the real farm-value definition is not known.
  static const double farmValueSpentWeight = 1.0;

  /// PLACEHOLDER: the real farm-value definition is not known.
  static const double farmValueIncomeExponent = 0.8;

  /// PLACEHOLDER: the real farm-value definition is not known.
  static const double farmValueIncomeWindowSec = 600;
  static const double droneSmallFarmValueFraction = 0.02;
  static const double droneMediumFarmValueFraction = 0.10;
  static const double droneLargeFarmValueFraction = 0.30;
  static const int balanceSimulationPaybackLookaheadSeconds = 300;

  /// TUNABLE: old-version Soul Egg calculation power from the project spec.
  static const double soulEggGainExponent = 0.15;
  static const double soulEggCashDivisor = 1000000;

  /// TUNABLE: base Soul Egg bonus before Soul Food research.
  static const double basePerSoulEggEarningsBonus = 0.10;

  /// TUNABLE: the "1 +" in the earnings-multiplier formula.
  static const double baseEarningsMultiplier = 1;

  /// TUNABLE: base Prophecy Egg exponent before Prophecy Bonus research.
  static const double baseProphecyEggMultiplier = 1.05;

  /// PLACEHOLDER: regular drone arrival interval before random jitter.
  static const double droneSpawnIntervalSec = 15;

  /// PLACEHOLDER: symmetric random jitter applied to drone arrival intervals.
  static const double droneSpawnJitterFraction = 0.30;

  /// PLACEHOLDER: how long the drone is visible and tappable.
  static const double droneFlightDurationSec = 0.5;

  /// PLACEHOLDER: regular drone reward odds.
  static const double droneGoldenEggChance = 0.30;

  /// PLACEHOLDER: rare elite drone chance.
  static const double droneEliteChance = 0.03;

  /// PLACEHOLDER: normal drone reward values and tier weights.
  static const List<double> droneGoldenEggRewards = [3, 6, 12];
  static const List<double> droneGoldenEggTierWeights = [70, 25, 5];
  static const List<double> droneCashRewardFractions = [0.02, 0.10, 0.30];
  static const List<double> droneCashTierWeights = [70, 25, 5];

  /// PLACEHOLDER: elite drone Golden Egg outcomes and tier weights.
  static const List<double> eliteDroneGoldenEggRewards = [12, 48];
  static const List<double> eliteDroneTierWeights = [95, 5];

  /// PLACEHOLDER: faster taps and Drone Rewards shift weight to the top tier.
  static const double droneFastTapMaxWeightShift = 20;
  static const double droneEpicWeightShiftPerEffect = 5;

  /// PLACEHOLDER: low-cost boost tiers use these multipliers and price shares.
  static const List<double> placeholderBoostMultipliers = [2, 5, 10];
  static const List<double> placeholderBoostPriceFractions = [0.01, 0.03, 0.10];

  /// Chicken counts required for Bronze through Diamond trophies (wiki data).
  static const List<double> trophyChickenCountThresholds = [
    10e6,
    50e6,
    250e6,
    1e9,
    10e9,
  ];

  /// Trophy names in threshold order (wiki data).
  static const List<String> trophyTierNames = [
    'Bronze',
    'Silver',
    'Gold',
    'Platinum',
    'Diamond',
  ];

  /// Soul Egg trophy rewards by egg ID and trophy tier (wiki data).
  static const Map<String, List<double>> trophySoulEggRewards = {
    'edible': [2e6, 10e6, 100e6, 10e9],
    'superfood': [1e6, 5e6, 50e6, 2.5e9],
    'medical': [600e3, 3e6, 15e6, 1e9],
    'rocket_fuel': [300e3, 1.5e6, 6e6, 250e6],
    'super_material': [150e3, 750e3, 4e6, 100e6],
    'fusion': [100e3, 500e3, 2.5e6, 50e6],
    'quantum': [50e3, 250e3, 1e6, 10e6],
    'tachyon': [25e3, 175e3, 1e6, 10e6],
    'graviton': [10e3, 100e3, 1e6, 10e6, 25e9],
  };

  /// Golden Egg trophy rewards by egg ID and trophy tier (wiki data).
  static const Map<String, List<double>> trophyGoldenEggRewards = {
    'dilithium': [3e3, 4e3, 5e3, 10e3, 25e3],
    'prodigy': [3e3, 4e3, 5e3, 10e3, 20e3],
    'terraform': [3e3, 4e3, 5e3, 9e3, 17.5e3],
    'antimatter': [3e3, 4e3, 5e3, 8e3, 15e3],
    'dark_matter': [3e3, 4e3, 5e3, 7.5e3, 12.5e3],
    'ai': [3e3, 4e3, 5e3, 7e3, 10e3],
    'nebula': [3e3, 4e3, 5e3, 7e3, 10e3],
    'universe': [3e3, 4e3, 5e3, 7e3, 10e3],
  };

  /// Diamond Prophecy Egg rewards by egg ID (wiki data).
  static const Map<String, double> trophyProphecyEggRewards = {
    'edible': 5,
    'superfood': 4,
    'medical': 3,
    'rocket_fuel': 2,
    'super_material': 1,
    'fusion': 1,
    'quantum': 1,
    'crispr': 1,
    'tachyon': 1,
    'enlightenment': 10,
  };

  /// Enlightenment trophy Prophecy Egg rewards by tier (wiki data).
  static const List<double> enlightenmentTrophyProphecyEggRewards = [
    1,
    2,
    3,
    5,
    10,
  ];

}
