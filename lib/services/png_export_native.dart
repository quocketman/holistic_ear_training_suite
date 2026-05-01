import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Saves PNG bytes to a user-chosen location via a native save dialog.
/// Returns the chosen file path. Throws if the user cancels.
Future<String> savePngBytes({
  required String filename,
  required Uint8List bytes,
}) async {
  const typeGroup = XTypeGroup(label: 'PNG image', extensions: ['png']);
  final location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: [typeGroup],
  );
  if (location == null) {
    throw const _SaveCancelled();
  }

  // Ensure the path ends with .png.
  var path = location.path;
  if (!path.toLowerCase().endsWith('.png')) {
    path = '$path.png';
  }

  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Sentinel exception used when the user dismisses the save dialog.
class _SaveCancelled implements Exception {
  const _SaveCancelled();
  @override
  String toString() => 'Save cancelled';
}
