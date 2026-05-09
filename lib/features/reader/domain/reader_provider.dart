import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../core/authenticated_http_client.dart';
import '../../../core/markdown_parser.dart';
import '../../auth/domain/auth_state.dart';
import '../../cache/domain/cache_provider.dart';
import '../../vault/data/vault_repository.dart';
import '../../vault/domain/vault_models.dart';
import '../../vault/domain/vault_provider.dart';
import '../data/note_content_repository.dart';

final currentNoteProvider = StateProvider<Note?>((ref) {
  return null;
});

/// Tracks navigation history for the Back button.
/// Each time a note is opened from another note, push the previous note here.
/// Popping goes back to the previous note.
final noteHistoryProvider = StateProvider<List<Note>>((ref) => []);

final driveFileContentClientProvider = Provider<DriveFileContentClient>((ref) {
  final authState = ref.watch(authControllerProvider);
  final user = authState.user;
  if (user == null) {
    throw StateError('Google Drive requires an authenticated user.');
  }

  final client = AuthenticatedHttpClient(
    headers: user.authHeaders,
    onAuthError: () async {
      final repo = ref.read(authRepositoryProvider);
      try {
        final refreshedUser = await repo.refreshToken();
        return refreshedUser.authHeaders;
      } catch (_) {
        // Refresh failed — trigger redirect to login
        ref.read(authControllerProvider.notifier).forceSignOut();
        return null;
      }
    },
  );
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

final forceRefreshNoteProvider = FutureProvider.family<void, Note>((
  ref,
  note,
) async {
  final repo = ref.read(noteContentRepositoryProvider);
  await repo.forceRefresh(note);
  ref.invalidate(noteContentProvider(note));
});

final backgroundRevalidateProvider = FutureProvider.family<String?, Note>((
  ref,
  note,
) {
  return ref.watch(noteContentRepositoryProvider).revalidateIfNeeded(note);
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

/// Indexes wikilinks for [note] and returns backlinks (other notes linking to it).
/// Depends on note content being available.
final backlinksProvider = FutureProvider.family<List<BacklinkEntry>, Note>((
  ref,
  note,
) async {
  // Ensure content is loaded first
  final content = await ref.watch(noteContentProvider(note).future);
  final vaultRepo = ref.watch(vaultRepositoryProvider);

  // Index wikilinks from this note's content
  await vaultRepo.indexWikilinks(note.id, content, note.vaultId);

  // Query which notes link TO this note
  return vaultRepo.getBacklinks(note.id);
});
