import 'package:flutter/material.dart';

import 'data/game_data.dart';
import 'ui/game_screen.dart';

void main() {
  runApp(const EggEmpireApp());
}

class EggEmpireApp extends StatelessWidget {
  const EggEmpireApp({super.key, this.gameData});

  final GameData? gameData;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chickenville',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: GameScreen(data: gameData),
    );
  }
}
