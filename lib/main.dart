import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/musical_state.dart';
import 'screens/home_screen.dart';
import 'services/audio_service.dart';
import 'repositories/local_progress_repository.dart';

final localProgressRepository = LocalProgressRepository();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local storage
  await Hive.initFlutter();
  await localProgressRepository.init();

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
