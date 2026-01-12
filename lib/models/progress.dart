/// Tracks user progress in ear training exercises
class UserProgress {
  final String exerciseType;
  int totalAttempts;
  int correctAttempts;
  List<ExerciseResult> recentResults;

  UserProgress({
    required this.exerciseType,
    this.totalAttempts = 0,
    this.correctAttempts = 0,
    List<ExerciseResult>? recentResults,
  }) : recentResults = recentResults ?? [];

  /// Calculate accuracy percentage
  double get accuracy {
    if (totalAttempts == 0) return 0.0;
    return (correctAttempts / totalAttempts) * 100;
  }

  /// Add a new result
  void addResult(ExerciseResult result) {
    totalAttempts++;
    if (result.isCorrect) {
      correctAttempts++;
    }
    recentResults.add(result);
    
    // Keep only the last 50 results
    if (recentResults.length > 50) {
      recentResults.removeAt(0);
    }
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'exerciseType': exerciseType,
      'totalAttempts': totalAttempts,
      'correctAttempts': correctAttempts,
      'recentResults': recentResults.map((r) => r.toJson()).toList(),
    };
  }

  /// Create from JSON
  factory UserProgress.fromJson(Map<String, dynamic> json) {
    return UserProgress(
      exerciseType: json['exerciseType'] as String,
      totalAttempts: json['totalAttempts'] as int? ?? 0,
      correctAttempts: json['correctAttempts'] as int? ?? 0,
      recentResults: (json['recentResults'] as List<dynamic>?)
              ?.map((r) => ExerciseResult.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Represents the result of a single exercise attempt
class ExerciseResult {
  final String exerciseId;
  final bool isCorrect;
  final DateTime timestamp;
  final String? userAnswer;
  final String? correctAnswer;

  ExerciseResult({
    required this.exerciseId,
    required this.isCorrect,
    required this.timestamp,
    this.userAnswer,
    this.correctAnswer,
  });

  Map<String, dynamic> toJson() {
    return {
      'exerciseId': exerciseId,
      'isCorrect': isCorrect,
      'timestamp': timestamp.toIso8601String(),
      'userAnswer': userAnswer,
      'correctAnswer': correctAnswer,
    };
  }

  factory ExerciseResult.fromJson(Map<String, dynamic> json) {
    return ExerciseResult(
      exerciseId: json['exerciseId'] as String,
      isCorrect: json['isCorrect'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      userAnswer: json['userAnswer'] as String?,
      correctAnswer: json['correctAnswer'] as String?,
    );
  }
}
