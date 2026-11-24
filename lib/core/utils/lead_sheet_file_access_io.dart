import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

File _nativeFile(PlatformFile file) {
  final path = file.path;
  if (path == null || path.isEmpty) {
    throw StateError('The selected file is no longer available.');
  }
  return File(path);
}

UploadTask uploadLeadSheetFile(
  Reference reference,
  PlatformFile file,
  SettableMetadata metadata,
) =>
    reference.putFile(_nativeFile(file), metadata);

Future<Uint8List> readLeadSheetBytes(PlatformFile file) =>
    _nativeFile(file).readAsBytes();
