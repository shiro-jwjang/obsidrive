import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

import '../../../core/markdown_parser.dart';
import '../../auth/domain/auth_state.dart';
import '../../cache/domain/cache_provider.dart';
import '../../vault/domain/vault_models.dart';
import '../../vault/domain/vault_provider.dart';
import '../data/note_content_repository.dart';

final currentNoteProvider = StateProvider<Note?>((ref) {
  return null;
});

final driveFileContentClientProvider = Provider<DriveFileContentClient>((ref) {
  final authState = ref.watch(authControllerProvider);
  final user = authState.user;
  if (user == null) {
    throw StateError('Google Drive requires an authenticated user.');
  }

  final client = _AuthenticatedHttpClient(user.authHeaders);
  ref.onDispose(client.close);
  return GoogleDriveFileContentClient(drive.DriveApi(client));
});

final noteContentStoreProvider = Provider<NoteContentStore>((ref) {
  return VaultNoteContentStore(ref.watch(vaultRepositoryProvider));
});

final noteContentRepositoryProvider = Provider<NoteContentRepository>((ref) {
  return NoteContentRepository(
    store: ref.watch(noteContentStoreProvider),
    driveClient: ref.watch(driveFileContentClientProvider),
    cacheService: ref.watch(cacheServiceProvider),
    isOnline: () => ref.read(isOnlineProvider),
  );
});

final noteContentProvider = FutureProvider.family<String, Note>((ref, note) {
  return ref.watch(noteContentRepositoryProvider).getContent(note);
});

final vaultWikilinksProvider = FutureProvider.family<List<Note>, int>((
  ref,
  vaultId,
) {
  return ref.watch(noteContentStoreProvider).listNotes(vaultId);
});

final parsedWikilinksProvider = Provider.family<List<Wikilink>, String>((
  ref,
  markdown,
) {
  return parseWikilinks(markdown);
});

class _AuthenticatedHttpClient extends http.BaseClient {
  _AuthenticatedHttpClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
