# Prompt for VS Code Copilot: Egg-farm idle game (Flutter / Android)

Paste everything below into Copilot Chat (Agent mode). If it truncates, paste it section by section and say "continue with Section N".

---

## 0. Your role and working style

You are building a single-player idle/incremental game for **Android** using **Flutter (Dart)**. It reproduces the *mechanics* of the mobile game "Egg, Inc." Visuals do not need to match. Use simple original placeholder art (colored shapes, Material icons, emoji). **Do not use any Egg, Inc. names, logos, art or text.** Working title: "Egg Empire".

Work in the **phases listed in Section 12**. After each phase, make sure `flutter analyze` and `flutter test` pass, summarize what you did, and wait for me to say "next". Do not hard-code balance numbers in UI or logic code. I am supplying `common_research.json` and `epic_research.json`, so copy them into `assets/data/` first. All balance data lives in `assets/data/*.json` and `lib/config/balance.dart` so I can tune it. Where a value is marked **TUNABLE** or **PLACEHOLDER**, put it in config with a `// TODO: verify against wiki` comment.

## 1. Tech and architecture

- Flutter stable, Dart 3, null safety, Android target (min SDK 24).
- State management: **Riverpod** (or Provider if you prefer). Keep game logic in pure Dart classes under `lib/game/` with **no Flutter imports**, so it is unit-testable.
- Folder layout: `lib/game/` (engine, formulas, models), `lib/config/`, `lib/ui/` (screens, widgets), `lib/save/`, `assets/data/`, `test/`.
- **Numbers:** use `double` everywhere. Values stay under 1e308. Write a `formatNumber(double)` helper using the suffix ladder below, plus scientific notation above the last suffix.
  - Suffixes: `K=1e3, M=1e6, B=1e9, T=1e12, q=1e15, Q=1e18, s=1e21, S=1e24, o=1e27, N=1e30, d=1e33, U=1e36, D=1e39, Td=1e42`. Show 3 significant figures, e.g. `118.02`, `4.387Td`.
- **Game loop:** a ticker-driven fixed update (for example 10 ticks/sec of game logic, UI rebuilds throttled) using real delta time. Pause logic when the app is backgrounded, and compute offline progress on resume (Section 9).
- **Saving:** JSON save with a `version` field, autosave every 15 s and on `AppLifecycleState.paused`, using `shared_preferences` or Hive. Include a "Reset all data" button in Settings with confirmation.

## 2. Core economy model

State per run (a "run" is one farm on one egg type):

- `cash`, `cashEarnedThisPrestige` (cumulative across all egg upgrades since last prestige), `cashEarnedThisRun`
- `chickens` (double), `habs[tier][slot]`, `vehicles[...]`, `commonResearch levels`, `eggType`, `silos`, `hatcheryStock`
- Permanent state: `goldenEggs`, `soulEggs`, `prophecyEggs`, `epicResearch levels`, `trophies earned`

**How research multipliers combine (from the wiki):** every research item has a mode. `add` items give `1 + perLevel*level`; `mul` items ("DOUBLES/TRIPLES/10x egg value") give `perLevel^level`; `flat` items add `perLevel*level` into a named stat. Items with the same effect **multiply** each other (add/mul modes) or **sum** (flat). So all research compounds with other research. Epic research multiplies on top as its own factor.

Per-second formulas (**all multipliers come from the research JSON and config**):

```
layRateMult   = product(add-items effect=layRate, incl. Improved Genetics) * (1 + epicComfyNests)
eggValueMult  = product(add/mul items effect=eggValue, incl. Improved Genetics)
eggsLaidPerMin = chickens * 2 * layRateMult                       // base 2 eggs/min per chicken

vehicleCapMult = product(add-items effect=vehicleCapacity) * (1 + transportationLobbyists)
                 * vehicleSpeedMult   // ASSUMPTION: speed research multiplies shipping rate; verify
hoverBonus     = extra product(hoverVehicleCapacity) for Hover Semi, Quantum Transporter, Hyperloop Train only
                 (hyperloopVehicleCapacity for Hyperloop Train only)
shipCapacityPerMin = sum over vehicles(baseCapacity * vehicleCapMult * hoverBonus)
eggsShippedPerMin  = min(eggsLaidPerMin, shipCapacityPerMin)      // shipping is the bottleneck

cashPerSec = (eggsShippedPerMin / 60) * eggValue(eggType) * eggValueMult
             * earningsMultiplier * runningChickenMult * activeBoostEarningsMultiplier
```

If laid eggs exceed shipping capacity, show a visible "eggs backing up" indicator (the original's core tension: grow housing and transport together).

**Fleet size:** start with 4 slots. `flat` fleetSize research adds up to +13, for a total of **17** (verified: 2+2+2+2+5 = 13).

**Hab capacity:** `capacity = baseCap * product(habCapacity items)` (max x3.15). Planet Portal and Chicken Universe tiers also get `product(portalHabCapacity items)` (Wormhole Dampening, x1.5 max), giving the x4.725 max.

**Chickens come from two places:**

1. **Hatchery (manual):** a stock of ready chickens, capped at `hatcheryCapacity` (base 250 per an older wiki note, **verify**, plus `flat` research). It refills at `hatcheryRefillPerMin * hatcheryRefillMult` (base refill rate **PLACEHOLDER**, `hatcheryRefillMult = product(add-items) * (1 + epicHatchery)`). Tapping spends stock and adds chickens (hold-to-repeat at `holdHatchPerSec` from Hold to Hatch epic, base rate **PLACEHOLDER**).
2. **Internal hatcheries (automatic):** `ihrPerHab = sum(flat ihrPerHab research) * (1 + epicIntHatcheries)` chickens/min **per hab**. Total = `ihrPerHab * numberOfHabs`, capped by total hab capacity. While offline multiply by `(1 + internalHatcheryCalm)`. Verified: all common IHR research sums to 3,720 per hab, and Epic Int. Hatcheries doubles it to 7,440.

**Running chicken bonus (optional, do in Phase 8):** chickens hatched by tapping "run" across the farm for `runDurationSec` (**PLACEHOLDER** 15). The bonus only applies while habs are **not full**.
`runningChickenMult = clamp(1 + running * perChickenBonus, 1, maxRunningBonus)`.
`perChickenBonus = 0.005 (PLACEHOLDER) + 0.001*excitableLevels + 0.001*epicCluckingLevels`.
`maxRunningBonus = 5 + sum(flat maxRunningBonus research) + epicMultiplier` (verified: 5 + 335 common + 200 epic = **540x**, matching the wiki).

## 3. Housing (habitats), real wiki data

19 tiers, **4 slots each**. The price of a purchase depends on how many of *that tier* you already own (slot 1 to slot 4 prices below). Upgrading a hab to the next tier pays the next tier's price for the next free slot in that tier. Buying a hab adds its capacity. Research can raise capacity up to **x3.15** (x4.725 for the last two tiers, see "maxMult").

Prices are in cash, using the suffix ladder in Section 1. Put this table in `assets/data/habs.json`.

| # | Tier | Base cap | maxMult | Slot 1 | Slot 2 | Slot 3 | Slot 4 |
|---|---|---|---|---|---|---|---|
| 1 | Coop | 250 | 3.15 | 13.78 | 35.6 | 68.89 | 118.02 |
| 2 | Shack | 500 | 3.15 | 569 | 982 | 1,536 | 2,276 |
| 3 | Super Shack | 1,000 | 3.15 | 14,991 | 28,760 | 49,987 | 81,658 |
| 4 | Short House | 2,000 | 3.15 | 416,571 | 896,836 | 1,734,149 | 3,118,140 |
| 5 | The Standard | 5,000 | 3.15 | 26,204,460 | 83,270,224 | 217.759M | 499.867M |
| 6 | Long House | 10,000 | 3.15 | 2.835B | 7.282B | 16.313B | 33.237B |
| 7 | Double Decker | 20,000 | 3.15 | 106.766B | 479.517B | 1.101T | 2.282T |
| 8 | Warehouse | 50,000 | 3.15 | 21.747T | 80.776T | 237.291T | 593.84T |
| 9 | Center | 100,000 | 3.15 | 3.96q | 10.698q | 24.929q | 52.427q |
| 10 | Bunker | 200,000 | 3.15 | 305.816q | 827.007q | 1.928Q | 4.058Q |
| 11 | Eggkea | 500,000 | 3.15 | 39.804Q | 149.127Q | 440.336Q | 1.105s |
| 12 | HAB 1000 | 1,000,000 | 3.15 | 7.389s | 19.949s | 46.44s | 97.536s |
| 13 | Hangar | 2,000,000 | 3.15 | 566.256s | 1.527S | 3.511S | 7.449S |
| 14 | Tower | 5,000,000 | 3.15 | 72.433S | 269.16S | 781.351S | 1.927o |
| 15 | HAB 10,000 | 10,000,000 | 3.15 | 15.238o | 46.284o | 117.291o | 262.293o |
| 16 | Eggtopia | 25,000,000 | 3.15 | 3.58N | 15.709N | 51.253N | 137.98N |
| 17 | Monolith | 50,000,000 | 3.15 | 3.424d | 19.091d | 72.407d | 214.32d |
| 18 | Planet Portal | 100,000,000 | 4.725 | 10.478U | 71.722U | 291.813U | 877.951U |
| 19 | Chicken Universe | 600,000,000 | 4.725 | 393.113D | 4.387Td | 23.74Td | 87.067Td |

Rules: start with one Coop. Each hab purchase adds +25 to the Piggy Bank (Section 8, optional). A "Cheaper Contractors" epic research reduces hab prices (Section 7).

## 4. Transportation (vehicles)

12 vehicle tiers. Start with 1 Trike and **4 vehicle slots**; research raises slots up to **17**. Capacity is in eggs/min. Put this in `assets/data/vehicles.json`.

| # | Vehicle | Capacity (eggs/min) | First-unit price |
|---|---|---|---|
| 1 | Trike | 5,000 | free (starting vehicle) |
| 2 | Transit Van | 15,000 | 544 |
| 3 | Pickup | 50,000 | 52,868 |
| 4 | 10 Foot | 100,000 | 14.962M |
| 5 | 24 Foot | 250,000 | 4.358B |
| 6 | Semi | 500,000 | 58.164T |
| 7 | Double Semi | 1,000,000 | 593.97q |
| 8 | Future Semi | 5,000,000 | 5.084s |
| 9 | Mega Semi | 15,000,000 | 33.474S |
| 10 | Hover Semi | 30,000,000 | 1.616N |
| 11 | Quantum Transporter | 50,000,000 | 5.576d |
| 12 | Hyperloop Train | 50,000,000 | 21.124U (treat as a normal vehicle; skip the train-car mechanic) |

**Price of the nth unit of a tier** (n = how many of that tier you own, 1-based): `price = firstPrice * curve(tier, n)`. I only have real per-slot data for some tiers, so use these normalized curves and **interpolate linearly by tier index** between them (tier 1 uses curve A, tier 12 uses curve B). Mark as **TUNABLE / PLACEHOLDER**:

- Curve A (from Trike): `1, 2.548, 5.147, 9.26, 15.71, 25.26, 39.16, 58.8, 86.2, 123.2, 172.8, 238.7, 312`
- Curve B (from Hover Semi): `1, 1.376, 1.855, 2.458, 3.209, 4.127, 5.242, 6.582, 8.174, 10.06, 12.26, 14.83, 17.80, 21.22`
- For n beyond the listed entries, extrapolate with a x1.2 growth per step.

Each vehicle purchase adds +20 to the Piggy Bank (optional). Vehicle capacity research multiplies all vehicle capacity.

## 5. Eggs and "ascending" (selling the farm for a better egg)

Put this in `assets/data/eggs.json`. `upgradeFarmValue` is the farm value you need to sell the farm and move to that egg.

| # | Egg | Value per egg | Farm value needed to upgrade TO it | Source |
|---|---|---|---|---|
| 1 | Edible | 0.25 | default | wiki |
| 2 | Superfood | 1.25 | 68M | wiki |
| 3 | Medical | 6.25 | 5.3B | wiki |
| 4 | Rocket Fuel | 30 | 240B | wiki |
| 5 | Super Material | 150 | 170T | wiki |
| 6 | Fusion | 700 | 45q | older wiki table, verify |
| 7 | Quantum | 3,000 | 2e19 | PLACEHOLDER |
| 8 | Immortality | 12,500 | 8e22 | older wiki table, verify |
| 9 | Tachyon | 50,000 | 1.3e26 | community guide, verify |

Build the egg list so more eggs can be appended via JSON only (later eggs: Graviton, Dilithium, Prodigy, ...).

**Ascend (egg upgrade):** when `farmValue >= nextEgg.upgradeFarmValue`, show an "Ascend" button. Ascending sells the farm: reset cash, chickens, habs, vehicles, common research, silos and run timers, and start a new run on the new egg. It does **not** grant Soul Eggs. Keep `cashEarnedThisPrestige` accumulating.

**Farm value (PLACEHOLDER, the real definition is not verified):**
`farmValue = totalSpentThisRun + incomePerSecondWithoutBoosts * 3600`. Make both terms and the 3600 TUNABLE, then multiply by `(1 + 0.05 * accountingTricksLevel)` (the wiki confirms Accounting Tricks raises farm valuation). Add a headless simulation test (`test/balance_sim_test.dart`) that plays a naive "buy the cheapest useful thing" bot and prints time-to-each-egg, so I can tune the pacing.

## 6. Prestige (Soul Eggs and Prophecy Eggs): compounding system

Prestige resets *everything* in the run and sends the player back to the **Edible** egg, awarding Soul Eggs. It keeps: golden eggs, soul eggs, prophecy eggs, epic research, trophies.

**Soul Eggs gained** (the old wiki formula; keep the exponent in config, **TUNABLE**, newer game versions use ~0.21 with an offset):

```
soulEggsGained = floor( prestigeBonusMult * activeSoulBeaconMult * (cashEarnedThisPrestige / 1e6) ^ 0.15 )
prestigeBonusMult = 1 + 0.10 * prestigeBonusEpicLevel      // 20 levels max => up to x3
```

Show a live "You would gain N Soul Eggs" on the Prestige screen, and a confirmation dialog.

**Earnings bonus (EB)** is where the compounding lives (Soul Eggs are **linear**, Prophecy Eggs **compound**):

```
perSoulEggBonus   = 0.10 + 0.01 * soulFoodEpicLevel          // Soul Food: 140 levels max => up to 1.50 per SE
prophecyBase      = 1.05 + 0.01 * prophecyBonusEpicLevel      // Prophecy Bonus: 5 levels max => up to 1.10
earningsBonus     = soulEggs * perSoulEggBonus * prophecyBase ^ prophecyEggs
earningsMultiplier = 1 + earningsBonus                         // the "1 +" is an assumption, TUNABLE
```

Sanity checks from the wiki: 100 SE with no upgrades gives EB of 1,000% (x11 with the "1 +"), and each Prophecy Egg multiplies EB by 1.05 to 1.10. Put these in unit tests.

**Prophecy Eggs source (replaces contracts, which are multiplayer):** trophies. Each egg has a "top chicken-count trophy". Reaching it once grants Prophecy Eggs: Edible 5, Superfood 4, Medical 3, Rocket Fuel 2, every egg after that 1. The chicken-count milestones are **PLACEHOLDER** (derive from hab capacity so they are reachable but hard). Also grant Golden Eggs for lesser trophies (TUNABLE).

## 7. Research

### Common research (resets on prestige AND on ascend, bought with cash)

Effects and max levels below are **real wiki data**. Put them in `assets/data/common_research.json` (I am supplying that file with this prompt; if it is missing, generate it from this table). **Costs and tier-unlock thresholds are NOT on the wiki page, so they are PLACEHOLDERS**: the JSON gives each item `firstCost` and `lastCost`, and the cost of level L is `firstCost * (lastCost/firstCost)^((L-1)/(maxLevel-1))` (one-level items cost `lastCost`). Tier N unlocks once total levels bought in earlier tiers on this farm reach `tierUnlockTotalLevels[N]` (also placeholder). Tune with the balance simulation. Each purchase adds +3 to the Piggy Bank (optional).

Notes: "Improved Genetics" boosts both lay rate and egg value. Hyperloop train-car and train-length research is skipped. `vehicleSpeed` research is included, but how it affects income is an assumption (Section 2).

| Tier | Name | Effect | Per level | Max levels |
|---|---|---|---|---|
| 1 | Comfortable Nests | `layRate` | +10%/lvl | 50 |
| 1 | Nutritional Supplements | `eggValue` | +25%/lvl | 40 |
| 1 | Better Incubators | `hatcheryRefill` | +10%/lvl | 15 |
| 1 | Excitable Chickens | `runningBonusPerChicken` | +0.001/lvl | 25 |
| 2 | Hen House Remodel | `habCapacity` | +5%/lvl | 8 |
| 2 | Internal Hatcheries | `ihrPerHab` | +2/lvl | 10 |
| 2 | Padded Packaging | `eggValue` | +25%/lvl | 30 |
| 2 | Hatchery Expansion | `hatcheryCapacity` | +10/lvl | 10 |
| 2 | Bigger Eggs | `eggValue` | x2/lvl | 1 |
| 3 | Internal Hatchery Upgrades | `ihrPerHab` | +5/lvl | 10 |
| 3 | Improved Leafsprings | `vehicleCapacity` | +5%/lvl | 30 |
| 3 | Vehicle Reliability | `fleetSize` | +1/lvl | 2 |
| 3 | Rooster Booster | `hatcheryRefill` | +5%/lvl | 25 |
| 3 | Coordinated Clucking | `maxRunningBonus` | +0.2/lvl | 50 |
| 4 | Hatchery Rebuild | `hatcheryCapacity` | +50/lvl | 1 |
| 4 | USDE Prime Certification | `eggValue` | x3/lvl | 1 |
| 4 | Hen House A/C | `layRate` | +5%/lvl | 50 |
| 4 | Super-Feed Diet | `eggValue` | +25%/lvl | 35 |
| 4 | Microlux Chicken Suites | `habCapacity` | +5%/lvl | 10 |
| 5 | Compact Incubators | `hatcheryCapacity` | +10/lvl | 10 |
| 5 | Lightweight Boxes | `vehicleCapacity` | +10%/lvl | 40 |
| 5 | Depot Worker Exoskeletons | `fleetSize` | +1/lvl | 2 |
| 5 | Internal Hatchery Expansion | `ihrPerHab` | +10/lvl | 15 |
| 5 | Improved Genetics | `layRate+eggValue` | +15%/lvl | 30 |
| 6 | Traffic Management | `fleetSize` | +1/lvl | 2 |
| 6 | Motivational Clucking | `maxRunningBonus` | +0.5/lvl | 50 |
| 6 | Driver Training | `vehicleSpeed` | +5%/lvl | 30 |
| 6 | Shell Fortification | `eggValue` | +15%/lvl | 60 |
| 7 | Egg Loading Bots | `fleetSize` | +1/lvl | 2 |
| 7 | Super Alloy Frames | `vehicleCapacity` | +5%/lvl | 50 |
| 7 | Even Bigger Eggs | `eggValue` | x2/lvl | 5 |
| 7 | Internal Hatchery Expansion II | `ihrPerHab` | +25/lvl | 30 |
| 8 | Quantum Egg Storage | `vehicleCapacity` | +5%/lvl | 20 |
| 8 | Genetic Purification | `eggValue` | +10%/lvl | 100 |
| 8 | Machine Learning Incubators | `ihrPerHab` | +5/lvl | 250 |
| 8 | Time Compression | `layRate` | +10%/lvl | 20 |
| 9 | Hover Upgrades | `hoverVehicleCapacity` | +5%/lvl | 25 |
| 9 | Graviton Coating | `eggValue` | x2/lvl | 7 |
| 9 | Grav Plating | `habCapacity` | +2%/lvl | 25 |
| 9 | Crystalline Shelling | `eggValue` | +25%/lvl | 100 |
| 10 | Autonomous Vehicles | `fleetSize` | +1/lvl | 5 |
| 10 | Neural Linking | `ihrPerHab` | +50/lvl | 30 |
| 10 | Telepathic Will | `eggValue` | +25%/lvl | 50 |
| 10 | Enlightened Chickens | `maxRunningBonus` | +2/lvl | 150 |
| 11 | Dark Containment | `vehicleCapacity` | +5%/lvl | 25 |
| 11 | Atomic Purification | `eggValue` | +10%/lvl | 50 |
| 11 | Multiversal Layering | `eggValue` | x10/lvl | 3 |
| 11 | Timeline Diversion | `layRate` | +2%/lvl | 50 |
| 12 | Wormhole Dampening | `portalHabCapacity` | +2%/lvl | 25 |
| 12 | Eggsistor Miniaturization | `eggValue` | +5%/lvl | 100 |
| 12 | Neural Net Refinement | `vehicleSpeed` | +5%/lvl | 25 |
| 13 | Matter Reconfiguration | `eggValue` | +1%/lvl | 500 |
| 13 | Timeline Splicing | `eggValue` | x10/lvl | 1 |
| 13 | Hyper Portalling | `hyperloopVehicleCapacity` | +5%/lvl | 25 |
| 13 | Relativity Optimization | `layRate` | +10%/lvl | 10 |

### Epic research (permanent, bought with Golden Eggs)

Real per-level effects and **real total Golden Egg costs** (cost for all levels) are in `assets/data/epic_research.json`. The wiki states the per-level cost rule: `cost(L) = floor((L-1)*(last-first)/(levels-1)) + first`. First and last are only known for Prophecy Bonus (100k, 325k, 550k, 775k, 1M). For the others the JSON assumes `last = 10*first` so the sum matches the real total; mark **PLACEHOLDER**. Apply `GOLDEN_EGG_COST_SCALE` (default 0.01) to every Golden Egg price at runtime, because the real total is 10.5M GE.

| Name | Max lvl | Effect per level | Real total GE |
|---|---|---|---|
| Soul Food | 140 | +1% bonus per Soul Egg (10% base to 150%) | 384,931 |
| Prestige Bonus | 20 | +10% Soul Eggs gained | 99,991 |
| Prophecy Bonus | 5 | +1% per Prophecy Egg (1.05 to 1.10, compounding) | 2,750,000 |
| Epic Comfy Nests | 20 | +5% lay rate | 502,491 |
| Epic Int. Hatcheries | 20 | +5% internal hatchery rate | 25,241 |
| Internal Hatchery Calm | 20 | +10% internal hatchery rate while away | 20,091 |
| Epic Hatchery | 20 | +10% hatchery refill rate | 10,011 |
| Hold to Hatch | 15 (inferred) | +2 chickens/sec when holding | 3,825 |
| Epic Clucking | 20 | +0.1% running bonus per chicken | 50,191 |
| Epic Multiplier | 100 (inferred) | +2.0 max running bonus | 500,455 |
| Cheaper Contractors | 10 | -5% hab prices | 10,100 |
| Bust Unions | 10 | -5% vehicle prices | 10,100 |
| Lab Upgrade | 10 | -5% common research prices | 10,121 |
| Silo Capacity | 20 | +6 min away time per silo | 14,991 |
| Accounting Tricks | 20 | +5% farm value | 42,941 |
| Drone Rewards | 20 | +10% chance of bigger drone rewards | 21,000 |
| Transportation Lobbyists | 30 | +5% vehicle capacity | 63,736 |

Skipped: Video Doubler Time, Hold to Research, Internal Hatchery Sharing, and the two spaceship-mission upgrades.

## 8. Drone event and Golden Eggs (the random bonus button)

- Every **~15 seconds** (TUNABLE `droneSpawnIntervalSec`, with +/-30% random jitter), spawn a **drone** that flies across the screen over ~6-8 s (TUNABLE). The player must tap it before it leaves. A faster drone gives a better reward tier.
- On tap, roll the reward: **30% gold, 70% cash** (real game ratio, TUNABLE).
  - **Gold:** 3, 6 or 12 Golden Eggs (regular drone; weights TUNABLE, faster drone shifts toward 12). Rare **elite drone** (TUNABLE, about 3% of spawns): 12 or 48 GE.
  - **Cash:** farmValue x {0.02, 0.10, 0.30} with weights {70%, 25%, 5%} (PLACEHOLDER).
- "Drone Rewards" epic research adds +10% per level to the **chance of bigger reward tiers** (shift the weights toward the larger gold amounts and the 0.30x cash roll; do not just multiply the amounts).
- Show a floating "+N Golden Eggs" popup and a particle burst. Golden Eggs persist across prestige.
- **Optional Piggy Bank:** a bank that gains Golden Eggs per purchase (+3 research, +20 vehicle, +25 hab, +25 boost). The player can "crack" it to claim the contents. Implement last; make it feature-flagged.

## 9. Boosts (spend Golden Eggs for temporary multipliers)

`assets/data/boosts.json`. Real multipliers and durations, with a real (unscaled) GE price shown. Apply `GOLDEN_EGG_COST_SCALE` at runtime.

| Boost | Effect | Duration | Real GE price |
|---|---|---|---|
| Jimbo's Best Bird Feed | earnings x50 | 10 min | ~2,500 |
| Tachyon Prism | internal hatchery rate x1000 | 10 min | ~12,000 |
| Boost Beacon | multiplies the multipliers of other active boosts by x50 | 10 min | ~50,000 |
| Soul Beacon | Soul Eggs gained on prestige x500 (while active) | 10 min | ~10,000 |

Rules: only one of each boost type runs at once (re-buying refreshes the timer). A Boost Beacon active together with another boost multiplies its effect (e.g. Tachyon x1000 * Beacon x50). Add 2 cheaper tiers per boost (Basic x2/x5, Large x10) as PLACEHOLDER so early game has useful sinks. Boost timers keep running offline, and show a countdown UI.

## 10. Offline progress

On resume or launch, compute elapsed time (cap by `silos * (siloBaseMinutes + 6 * siloCapacityEpicLevel)` minutes, with `siloBaseMinutes` and the silo count/prices PLACEHOLDER; the wiki confirms the Silo Capacity epic adds +6 min per silo per level). Simulate in chunks (for example 60 s steps up to 600 steps, then closed-form for the remainder): internal-hatchery chicken growth up to hab capacity, shipping bottleneck, boosts counting down. Show a "Welcome back, you earned X" dialog. Drones do not spawn offline.

## 11. UI screens (Material 3, portrait phone layout)

1. **Farm (home):** cash and cash/sec at the top; egg type and farm value progress bar toward the next egg; hatchery button; animated chickens (simple sprites or emoji, capped at ~60 drawn); hab list with buy/upgrade; the drone flying layer; "eggs backing up" warning.
2. **Vehicles:** list per slot, buy/upgrade, total capacity vs lay rate.
3. **Research:** tabs for Common and Epic, with level, cost and effect preview.
4. **Boosts:** buy/active countdowns.
5. **Prestige:** live SE gain preview, current EB, SE/PE/Soul Food stats, Prestige button; and the **Ascend** button when eligible.
6. **Trophies and Stats:** milestones, lifetime stats.
7. **Settings:** reset, number format (suffix vs scientific), offline summary toggle.

## 12. Phases (stop and wait for "next" after each)

1. **Scaffold + data:** project setup, folders, JSON loaders, `formatNumber` with tests, all data tables above loaded and validated by tests.
2. **Engine core:** state model, tick loop, lay/ship/cash formulas, hatchery, habs and vehicles purchasing, unit tests.
3. **Common research (load the supplied JSON) + Farm UI** playable end-to-end for the Edible egg, including internal hatcheries and fleet size.
4. **Ascend (egg upgrades) + farm value + balance sim test.**
5. **Prestige, Soul/Prophecy Eggs, EB formula, epic research, trophies.** Include the unit tests from Section 6.
6. **Drones + Golden Eggs + Boosts.**
7. **Offline progress + save/load + lifecycle handling.**
8. **Running chicken bonus, then polish:** Piggy Bank (optional), settings, app icon, release build instructions (`flutter build apk --release`).

## 13. Quality bar

- Pure-Dart game logic with unit tests for: number formatting, hab/vehicle pricing, shipping bottleneck, soul egg gain, EB with Prophecy compounding, ascend/prestige resets, offline simulation.
- No magic numbers in logic; everything reads from config or JSON.
- Keep functions small, add doc comments for every formula with the source (wiki or PLACEHOLDER).
- At the end of each phase, list any value you had to invent, so I can verify it.
