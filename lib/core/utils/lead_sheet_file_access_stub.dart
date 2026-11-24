import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

UploadTask uploadLeadSheetFile(
  Reference reference,
  PlatformFile file,
  SettableMetadata metadata,
) {
  final bytes = file.bytes;
  if (bytes == null) {
    throw StateError('Unable to read the selected file.');
  }
  return reference.putData(bytes, metadata);
}

Future<Uint8List> readLeadSheetBytes(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes == null) {
    throw StateError('Unable to read the selected file.');
  }
  return bytes;
}
