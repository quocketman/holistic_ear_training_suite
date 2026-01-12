# Ear Training App

A Flutter-based mobile application for practicing and assessing musical ear training skills.

## Features

- **Interval Recognition**: Practice identifying musical intervals
- **Chord Identification**: Learn to recognize different chord types
- **Rhythm Training**: Develop your sense of rhythm and timing
- **Progress Tracking**: Monitor your improvement over time

## Prerequisites

Before running this app, make sure you have Flutter installed:

1. Install Flutter: https://docs.flutter.dev/get-started/install
2. Verify installation: `flutter doctor`

## Getting Started

### Installation

1. Clone or download this repository
2. Navigate to the project directory:
   ```bash
   cd "Assessment Tool"
   ```

3. Install dependencies:
   ```bash
   flutter pub get
   ```

### Running the App

To run the app on an emulator or connected device:

```bash
flutter run
```

To run in debug mode:
```bash
flutter run --debug
```

To run in release mode:
```bash
flutter run --release
```

### Running on Specific Platforms

- **iOS**: `flutter run -d ios`
- **Android**: `flutter run -d android`
- **Web**: `flutter run -d chrome`
- **macOS**: `flutter run -d macos`

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── screens/                  # UI screens
│   └── home_screen.dart      # Home screen with exercise selection
├── models/                   # Data models
│   ├── exercise.dart         # Exercise models (intervals, chords)
│   └── progress.dart         # User progress tracking
├── services/                 # Business logic
│   └── audio_service.dart    # Audio playback service
└── widgets/                  # Reusable UI components
    └── audio_player_widget.dart
```

## Adding Audio Assets

To add audio files for exercises:

1. Create an `assets/audio/` directory in the project root
2. Add your audio files organized by exercise type:
   ```
   assets/
   └── audio/
       ├── intervals/
       ├── chords/
       └── rhythms/
   ```

3. Uncomment the assets section in `pubspec.yaml` and update paths

## Development

### Key Dependencies

- **just_audio**: Low-latency audio playback
- **audioplayers**: Alternative audio player
- **provider**: State management

### Next Steps

1. Implement interval recognition screen
2. Add audio file generation or recording
3. Implement chord identification exercises
4. Add rhythm training module
5. Integrate progress tracking with local storage
6. Add difficulty levels and adaptive learning

## Testing

Run tests with:
```bash
flutter test
```

## Building for Production

### Android
```bash
flutter build apk --release
```

### iOS
```bash
flutter build ios --release
```

### Web
```bash
flutter build web
```

## Troubleshooting

If you encounter issues:

1. Run `flutter doctor` to check your setup
2. Run `flutter clean` and then `flutter pub get`
3. Make sure your device/emulator is properly connected: `flutter devices`

## License

This project is for educational purposes.

## Contributing

Feel free to submit issues and enhancement requests!
