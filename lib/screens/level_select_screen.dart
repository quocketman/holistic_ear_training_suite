import 'package:flutter/material.dart';
import '../models/level_specs.dart';
import '../models/enums.dart';
import '../widgets/connection_visualizer.dart';
import 'practice_screen.dart';

class LevelSelectScreen extends StatelessWidget {
  const LevelSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Level'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FutureBuilder<List<LevelSpecs>>(
        future: LevelSpecs.loadAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final levels = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: levels.length,
            itemBuilder: (context, index) {
              final level = levels[index];
              return _LevelCard(level: level, allLevels: levels, index: index);
            },
          );
        },
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final LevelSpecs level;
  final List<LevelSpecs> allLevels;
  final int index;

  const _LevelCard({required this.level, required this.allLevels, required this.index});

  @override
  Widget build(BuildContext context) {
    final icon = switch (level.levelType) {
      LevelType.warmUp => Icons.wb_sunny_outlined,
      LevelType.practice => Icons.fitness_center,
      LevelType.challenge => Icons.flash_on,
      _ => Icons.music_note,
    };

    final color = switch (level.levelType) {
      LevelType.warmUp => Colors.amber,
      LevelType.practice => Colors.lightBlueAccent,
      LevelType.challenge => Colors.redAccent,
      _ => Colors.white70,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 1,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PracticeScreen(levelSpecs: level, allLevels: allLevels, currentLevelIndex: index),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white38,
                    ),
                  ),
                ),
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    level.levelTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 80,
                  child: ConnectionVisualizer(
                    levelSpecs: level,
                    mode: level.preferredMode ?? Mode.major,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
