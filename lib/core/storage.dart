/// Platform-agnostic file storage interface.
///
/// Implementations are provided for IO (mobile/desktop) and web platforms.
/// This decouples [CacheService] from `dart:io`, enabling web support.
abstract class FileStorage {
  Future<String> readString(String path);
  Future<void> writeString(String path, String content);
  Future<bool> exists(String path);
  Future<int> length(String path);
  Future<String> getCacheDirectory();
}
