// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:isolate';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run flutter_readium_web:copy_js_file <destination_directory>');
    return;
  }

  final destinationDir = args[0];
  final packageUri = Uri.parse('package:flutter_readium_web/helpers/readiumReader.js');
  final resolvedUri = await Isolate.resolvePackageUri(packageUri);

  if (resolvedUri == null) {
    print('Error: Could not resolve package URI');
    return;
  }

  final sourcePath = resolvedUri.toFilePath();
  final sourceFile = File(sourcePath);

  if (!sourceFile.existsSync()) {
    print('Error: Source file not found: $sourcePath');
    return;
  }

  final destinationPath = '$destinationDir/readiumReader.js';
  // final destinationFile = File(destinationPath);

  try {
    // Ensure the destination directory exists
    Directory(destinationDir).createSync(recursive: true);

    // Copy the file
    sourceFile.copySync(destinationPath);
    print('File copied to $destinationPath');
  } catch (e) {
    print('Error copying file: $e');
  }
}
