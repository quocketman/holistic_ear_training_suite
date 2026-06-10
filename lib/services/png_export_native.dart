import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Saves PNG bytes to a user-chosen location via a native save dialog.
/// Returns the chosen file path. Throws if the user cancels.
Future<String> savePngBytes({
  required String filename,
  required Uint8List bytes,
}) async =>
    _saveBytes(
      filename: filename,
      bytes: bytes,
      typeLabel: 'PNG image',
      extension: 'png',
    );

Future<String> savePdfBytes({
  required String filename,
  required Uint8List bytes,
}) async =>
    _saveBytes(
      filename: filename,
      bytes: bytes,
      typeLabel: 'PDF document',
      extension: 'pdf',
    );

Future<String> _saveBytes({
  required String filename,
  required Uint8List bytes,
  required String typeLabel,
  required String extension,
}) async {
  final typeGroup = XTypeGroup(label: typeLabel, extensions: [extension]);
  final location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: [typeGroup],
  );
  if (location == null) {
    throw const _SaveCancelled();
  }
  var path = location.path;
  if (!path.toLowerCase().endsWith('.$extension')) {
    path = '$path.$extension';
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
