import 'package:flutter/material.dart';
import 'tone_token_demo_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Ear Training'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            const SizedBox(height: 20),
            const Text(
              'Welcome to Ear Training!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Select an exercise to begin practicing',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _buildExerciseCard(
              context,
              title: 'ToneToken Demo',
              description: 'View and interact with ToneToken graphics',
              icon: Icons.grid_on,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ToneTokenDemoScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildExerciseCard(
              context,
              title: 'Interval Recognition',
              description: 'Practice identifying musical intervals',
              icon: Icons.music_note,
              onTap: () {
                // TODO: Navigate to interval exercise
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming soon!')),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildExerciseCard(
              context,
              title: 'Chord Identification',
              description: 'Learn to recognize different chord types',
              icon: Icons.piano,
              onTap: () {
                // TODO: Navigate to chord exercise
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming soon!')),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildExerciseCard(
              context,
              title: 'Rhythm Training',
              description: 'Develop your sense of rhythm and timing',
              icon: Icons.graphic_eq,
              onTap: () {
                // TODO: Navigate to rhythm exercise
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming soon!')),
                );
              },
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
