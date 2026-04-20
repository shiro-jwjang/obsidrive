// coverage:ignore-file
import 'storage.dart';

/// Web implementation of [FileStorage] using an in-memory map.
///
/// On web there is no filesystem, so cached content lives in memory for the
/// duration of the session. For a production app this would be backed by
/// `package:web` (IndexedDB / Cache API), but an in-memory store is
/// sufficient for the current feature set.
class WebFileStorage implements FileStorage {
  final Map<String, String> _cache = {};

  @override
  Future<String> readString(String path) async => _cache[path] ?? '';

  @override
  Future<void> writeString(String path, String content) async =>
      _cache[path] = content;

  @override
  Future<bool> exists(String path) async => _cache.containsKey(path);

  @override
  Future<int> length(String path) async => _cache[path]?.length ?? 0;

  @override
  Future<String> getCacheDirectory() async => 'web_cache';
}
