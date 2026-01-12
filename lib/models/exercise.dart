/// Base class for all ear training exercises
abstract class Exercise {
  final String id;
  final String name;
  final String description;

  Exercise({
    required this.id,
    required this.name,
    required this.description,
  });

  /// Play the audio for this exercise
  Future<void> play();

  /// Check if the user's answer is correct
  bool checkAnswer(String answer);
}

/// Represents an interval recognition exercise
class IntervalExercise extends Exercise {
  final String intervalType; // e.g., "major third", "perfect fifth"
  final String audioPath;

  IntervalExercise({
    required super.id,
    required super.name,
    required super.description,
    required this.intervalType,
    required this.audioPath,
  });

  @override
  Future<void> play() async {
    // TODO: Implement audio playback
    throw UnimplementedError();
  }

  @override
  bool checkAnswer(String answer) {
    return answer.toLowerCase() == intervalType.toLowerCase();
  }
}

/// Represents a chord identification exercise
class ChordExercise extends Exercise {
  final String chordType; // e.g., "major", "minor", "diminished"
  final String audioPath;

  ChordExercise({
    required super.id,
    required super.name,
    required super.description,
    required this.chordType,
    required this.audioPath,
  });

  @override
  Future<void> play() async {
    // TODO: Implement audio playback
    throw UnimplementedError();
  }

  @override
  bool checkAnswer(String answer) {
    return answer.toLowerCase() == chordType.toLowerCase();
  }
}
