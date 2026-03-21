import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/musical_state.dart';
import 'screens/home_screen.dart';
import 'services/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize audio synthesizer
  await AudioService.initialize();
  
  runApp(const EarTrainingApp());
}

class EarTrainingApp extends StatelessWidget {
  const EarTrainingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MusicalState(),
      child: MaterialApp(
        title: 'Ear Training',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: Colors.black,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
