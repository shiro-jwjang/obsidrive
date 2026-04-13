import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;

import 'storage.dart';

/// IO (mobile/desktop) implementation of [FileStorage] using `dart:io`.
class IoFileStorage implements FileStorage {
  @override
  Future<String> readString(String path) => File(path).readAsString();

  @override
  Future<void> writeString(String path, String content) =>
      File(path).writeAsString(content, flush: true);

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<String> getCacheDirectory() async {
    final base = await _appDir();
    final dir = Directory('$base/offline_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> _appDir() async {
    final docDir = await path_provider.getApplicationDocumentsDirectory();
    return docDir.path;
  }
}
