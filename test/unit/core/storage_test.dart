import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/storage.dart';

void main() {
  group('FileStorage', () {
    test('fake storage follows read write exists length contract', () async {
      final storage = _FakeFileStorage(baseDir: '/tmp/obsidrive-cache');
      const path = '/tmp/obsidrive-cache/note.md';

      expect(await storage.exists(path), isFalse);
      expect(await storage.readString(path), isEmpty);
      expect(await storage.length(path), 0);
      expect(await storage.getCacheDirectory(), '/tmp/obsidrive-cache');

      await storage.writeString(path, '# Note');

      expect(await storage.exists(path), isTrue);
      expect(await storage.readString(path), '# Note');
      expect(await storage.length(path), 6);
    });

    test('writeString replaces existing content', () async {
      final storage = _FakeFileStorage(baseDir: '/tmp/obsidrive-cache');
      const path = '/tmp/obsidrive-cache/note.md';

      await storage.writeString(path, 'old');
      await storage.writeString(path, 'updated content');

      expect(await storage.readString(path), 'updated content');
      expect(await storage.length(path), 15);
    });
  });
}

class _FakeFileStorage implements FileStorage {
  _FakeFileStorage({required this.baseDir});

  final String baseDir;
  final Map<String, String> data = <String, String>{};

  @override
  Future<bool> exists(String path) async => data.containsKey(path);

  @override
  Future<String> getCacheDirectory() async => baseDir;

  @override
  Future<int> length(String path) async => data[path]?.length ?? 0;

  @override
  Future<String> readString(String path) async => data[path] ?? '';

  @override
  Future<void> writeString(String path, String content) async {
    data[path] = content;
  }
}
