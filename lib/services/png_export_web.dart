import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> savePngBytes({
  required String filename,
  required Uint8List bytes,
}) async =>
    _saveBlob(filename: filename, bytes: bytes, mime: 'image/png');

Future<String> savePdfBytes({
  required String filename,
  required Uint8List bytes,
}) async =>
    _saveBlob(filename: filename, bytes: bytes, mime: 'application/pdf');

Future<String> _saveBlob({
  required String filename,
  required Uint8List bytes,
  required String mime,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return filename;
}
