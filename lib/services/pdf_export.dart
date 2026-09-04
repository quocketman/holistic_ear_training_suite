import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'png_export_native.dart'
    if (dart.library.js_interop) 'png_export_web.dart' as platform;
import 'url_state.dart';

/// Captures the [RepaintBoundary] at [boundaryKey] and saves it as a PNG.
/// Returns the destination path/filename. Throws on cancellation.
Future<String> exportRepaintBoundaryToPng({
  required GlobalKey boundaryKey,
  required String filenamePrefix,
  double pixelRatio = 2.0,
}) async {
  final pngBytes = await _captureBoundaryPng(
    boundaryKey: boundaryKey,
    pixelRatio: pixelRatio,
  );
  final timestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final filename = '${filenamePrefix}_$timestamp.png';
  return platform.savePngBytes(filename: filename, bytes: pngBytes);
}

/// Captures the [RepaintBoundary] at [boundaryKey] to raw PNG bytes (no file
/// save). Used by the multi-page print export to grab each page image.
Future<Uint8List> captureBoundaryToPngBytes({
  required GlobalKey boundaryKey,
  double pixelRatio = 2.0,
}) =>
    _captureBoundaryPng(boundaryKey: boundaryKey, pixelRatio: pixelRatio);

Future<Uint8List> _captureBoundaryPng({
  required GlobalKey boundaryKey,
  required double pixelRatio,
}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('RepaintBoundary not found for export');
  }
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode source image');
  }
  return byteData.buffer.asUint8List();
}

/// Captures a [RepaintBoundary] (looked up via [boundaryKey]) into a PDF
/// containing the rendered image, the user's raw solfège text in the bottom
/// margin, and a clickable link back to tuneindigo.com.
///
/// The PDF page orientation follows the source image (landscape if wider
/// than tall, portrait otherwise). Save dialog uses the same platform
/// helper as the PNG export — only the bytes and extension differ.
Future<String> exportRepaintBoundaryToPdf({
  required GlobalKey boundaryKey,
  required String filenamePrefix,
  required String solfegeText,
  String? title,
  double pixelRatio = 2.0,
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('RepaintBoundary not found for export');
  }

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode source image');
  }
  final pngBytes = byteData.buffer.asUint8List();

  final pdfBytes = await _buildPdf(
    imagePng: pngBytes,
    sourceWidth: image.width.toDouble(),
    sourceHeight: image.height.toDouble(),
    title: title,
    solfegeText: solfegeText,
  );

  final timestamp =
      DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final filename = '${filenamePrefix}_$timestamp.pdf';

  return platform.savePdfBytes(filename: filename, bytes: pdfBytes);
}

/// Assembles a multi-page letter PDF from pre-rendered, letter-proportioned
/// page images (each already carries its 0.75" margins as whitespace). Each
/// page is full-bleed; a small clickable link sits in the bottom margin that
/// re-opens the melody in the Whiteboard.
Future<String> exportPrintPagesToPdf({
  required List<Uint8List> pageImages,
  required String filenamePrefix,
  required String solfegeText,
  String? title,
}) async {
  final pdf = pw.Document(
    title: title?.isNotEmpty == true ? title : 'Tune Indigo Whiteboard',
    author: 'Tune Indigo Whiteboard',
  );

  final linkUrl = solfegeText.trim().isEmpty
      ? 'https://whiteboard.tuneindigo.com'
      : buildSolfegeShareUrl(solfegeText.trim());

  for (final bytes in pageImages) {
    final image = pw.MemoryImage(bytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
              pw.Positioned(
                bottom: 22,
                left: 0,
                right: 0,
                child: pw.Center(
                  child: pw.UrlLink(
                    destination: linkUrl,
                    child: pw.Text(
                      'whiteboard.tuneindigo.com',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.blue700,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  final timestamp =
      DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
  final filename = '${filenamePrefix}_$timestamp.pdf';
  return platform.savePdfBytes(filename: filename, bytes: await pdf.save());
}

Future<Uint8List> _buildPdf({
  required Uint8List imagePng,
  required double sourceWidth,
  required double sourceHeight,
  String? title,
  required String solfegeText,
}) async {
  final pdf = pw.Document(
    title: title?.isNotEmpty == true ? title : 'Tune Indigo Whiteboard',
    author: 'Tune Indigo Whiteboard',
  );

  final image = pw.MemoryImage(imagePng);
  final isLandscape = sourceWidth >= sourceHeight;
  final pageFormat =
      (isLandscape ? PdfPageFormat.letter.landscape : PdfPageFormat.letter)
          .copyWith(
              marginTop: 36, marginBottom: 36, marginLeft: 36, marginRight: 36);

  pdf.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Captured Whiteboard image — fills the page above the footer.
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 14),
            // User's raw solfège text in the bottom margin. Kept small and
            // muted so it reads as a footer / provenance line.
            if (solfegeText.trim().isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
                child: pw.Text(
                  solfegeText.trim(),
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
            pw.SizedBox(height: 6),
            // Clickable link that re-opens the Whiteboard with this exact
            // solfège text pre-loaded — see lib/services/url_state.dart.
            pw.UrlLink(
              destination: solfegeText.trim().isEmpty
                  ? 'https://whiteboard.tuneindigo.com'
                  : buildSolfegeShareUrl(solfegeText.trim()),
              child: pw.Text(
                'Edit this in the Whiteboard — whiteboard.tuneindigo.com',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.blue700,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  return pdf.save();
}
