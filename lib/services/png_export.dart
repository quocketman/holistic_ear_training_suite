import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'png_export_native.dart'
    if (dart.library.js_interop) 'png_export_web.dart' as platform;

/// Captures a [RepaintBoundary] (looked up via [boundaryKey]) into a PNG and
/// saves it. Returns a human-readable destination string (file path on
/// desktop/mobile, filename on web).
Future<String> exportRepaintBoundaryToPng({
  required GlobalKey boundaryKey,
  required String filenamePrefix,
  double pixelRatio = 1.0,
}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('RepaintBoundary not found for export');
  }

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode PNG');
  }
  final bytes = byteData.buffer.asUint8List();

  final timestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final filename = '${filenamePrefix}_$timestamp.png';

  return platform.savePngBytes(filename: filename, bytes: bytes);
}
