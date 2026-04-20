// coverage:ignore-file
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/vault_models.dart';
import '../domain/vault_provider.dart';

/// Folder tree widget with lazy-loaded .md files per folder.
class FolderTreeWidget extends ConsumerStatefulWidget {
  const FolderTreeWidget({
    required this.vault,
    required this.folders,
    required this.notes,
    super.key,
  });

  final Vault vault;
  final List<DriveFolder> folders;
  final List<Note> notes;

  @override
  ConsumerState<FolderTreeWidget> createState() => _FolderTreeWidgetState();
}

class _FolderTreeWidgetState extends ConsumerState<FolderTreeWidget> {
  @override
  Widget build(BuildContext context) {
    final root = _buildFolderTree(widget.folders, widget.notes);
    _logTreeDiagnostics(root);
    final children = root.sortedChildren;

    if (children.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref
            .read(vaultScannerProvider)
            .manualRefresh(
              vaultId: widget.vault.id,
              rootFolderId: widget.vault.driveFolderId,
              vaultName: widget.vault.name,
            ),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 80),
            Center(child: Text('표시할 마크다운 파일이 없습니다.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref
          .read(vaultScannerProvider)
          .manualRefresh(
            vaultId: widget.vault.id,
            rootFolderId: widget.vault.driveFolderId,
            vaultName: widget.vault.name,
          ),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 500,
        children: <Widget>[
          for (final child in children)
            _TreeNodeTile(node: child, depth: 0, vault: widget.vault),
        ],
      ),
    );
  }

  _TreeFolder _buildFolderTree(List<DriveFolder> folders, List<Note> notes) {
    final root = _TreeFolder('');

    // Build folder hierarchy from flat list
    final folderById = <String, _TreeFolder>{};

    for (final folder in folders) {
      final node = _TreeFolder(folder.name);
      node.driveFolderId = folder.id;
      node.parentId = folder.parentId;
      folderById[folder.id] = node;
    }

    // Organize into tree structure
    for (final folder in folders) {
      final node = folderById[folder.id]!;
      if (folder.parentId != null && folderById.containsKey(folder.parentId)) {
        node.parent = folderById[folder.parentId]!;
        folderById[folder.parentId]!.folders[folder.name] = node;
      } else if (folder.parentId == widget.vault.driveFolderId) {
        // Direct child of vault root
        node.parent = root;
        root.folders[folder.name] = node;
      }
    }

    // Add notes to their respective folders
    for (final note in notes.where((note) => _isMarkdownPath(note.filePath))) {
      _addNoteToTree(root, note);
    }

    return root;
  }

  void _addNoteToTree(_TreeFolder root, Note note) {
    final parts = note.filePath.split('/');
    var folder = root;
    for (final part in parts.take(parts.length - 1)) {
      folder = folder.folders.putIfAbsent(
        part,
        () => _TreeFolder(part, folder),
      );
    }
    folder.files.add(_TreeFile(parts.last, note));
  }

  static bool _isMarkdownPath(String path) {
    return path.toLowerCase().endsWith('.md');
  }

  void _logTreeDiagnostics(_TreeFolder root) {
    _consoleLog(
      '[FolderTree] vault id=${widget.vault.id} '
      'name="${widget.vault.name}" '
      'driveFolderId=${widget.vault.driveFolderId} '
      'folders=${widget.folders.length} notes=${widget.notes.length}',
    );

    for (final folder in widget.folders) {
      _consoleLog(
        '[FolderTree] folder id=${folder.id} '
        'name="${folder.name}" parentId=${folder.parentId}',
      );
    }

    for (final note in widget.notes) {
      _consoleLog(
        '[FolderTree] note id=${note.id} '
        'filePath="${note.filePath}" title="${note.title}" '
        'driveFileId=${note.driveFileId}',
      );
    }

    for (final child in root.sortedChildren) {
      _consoleLog(
        '[FolderTree] root child type=${child is _TreeFolder ? 'folder' : 'file'} '
        'name="${child.name}"',
      );
    }
  }

  void _consoleLog(String message) {
    // ignore: avoid_print
    print(message);
  }
}

class _TreeNodeTile extends ConsumerStatefulWidget {
  const _TreeNodeTile({
    required this.node,
    required this.depth,
    required this.vault,
  });

  final _TreeNode node;
  final int depth;
  final Vault vault;

  @override
  ConsumerState<_TreeNodeTile> createState() => _TreeNodeTileState();
}

class _TreeNodeTileState extends ConsumerState<_TreeNodeTile> {
  bool _hasLoadedFiles = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    if (node is _TreeFolder) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>(
            'folder:${node.driveFolderId ?? node.name}',
          ),
          leading: const Icon(Icons.folder_outlined),
          tilePadding: EdgeInsets.only(left: 16 + widget.depth * 20, right: 16),
          childrenPadding: EdgeInsets.zero,
          title: Row(
            children: <Widget>[
              Expanded(child: Text(node.name)),
              if (node.files.isNotEmpty)
                Text(
                  '${node.files.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
          onExpansionChanged: (expanded) {
            if (expanded && !_hasLoadedFiles) {
              _loadFolderFiles(node);
            }
          },
          children: <Widget>[
            for (final child in node.sortedChildren)
              _TreeNodeTile(
                node: child,
                depth: widget.depth + 1,
                vault: widget.vault,
              ),
          ],
        ),
      );
    }

    final file = node as _TreeFile;
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      contentPadding: EdgeInsets.only(left: 16 + widget.depth * 20, right: 16),
      title: Text(file.name),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () {
        context.push('/reader', extra: file.note);
      },
    );
  }

  void _loadFolderFiles(_TreeFolder folder) {
    final driveFolderId = folder.driveFolderId;
    if (driveFolderId == null) return;

    // Build the folder path for the query
    final folderPath = _buildFolderPath(folder);

    // Check if already loaded via provider
    final loadedIds = ref.read(loadedFolderIdsProvider);
    if (loadedIds.contains(driveFolderId)) {
      setState(() {
        _hasLoadedFiles = true;
      });
      return;
    }

    // Trigger the lazy load via the family provider
    ref.watch(
      folderNotesProvider(
        FolderLoadRequest(
          vaultId: widget.vault.id,
          driveFolderId: driveFolderId,
          folderPath: folderPath,
        ),
      ),
    );

    setState(() {
      _hasLoadedFiles = true;
    });
  }

  String _buildFolderPath(_TreeFolder folder) {
    return folder.path;
  }
}

sealed class _TreeNode {
  const _TreeNode(this.name);

  final String name;
}

class _TreeFolder extends _TreeNode {
  _TreeFolder(super.name, [this._parent]);

  final folders = <String, _TreeFolder>{};
  final files = <_TreeFile>[];
  String? driveFolderId;
  String? parentId;
  _TreeFolder? _parent;

  set parent(_TreeFolder? p) => _parent = p;

  /// Full path from root, e.g. "obsidian/jwjang/03 Projects"
  String get path {
    if (_parent == null || _parent!.name.isEmpty) return name;
    return '${_parent!.path}/$name';
  }

  List<_TreeNode> get sortedChildren {
    final children = <_TreeNode>[...folders.values, ...files];
    children.sort((a, b) {
      if (a is _TreeFolder && b is _TreeFile) {
        return -1;
      }
      if (a is _TreeFile && b is _TreeFolder) {
        return 1;
      }

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return children;
  }

  void add(Note note) {
    final parts = note.filePath.split('/');
    var folder = this;
    for (final part in parts.take(parts.length - 1)) {
      folder = folder.folders.putIfAbsent(
        part,
        () => _TreeFolder(part, folder),
      );
    }

    folder.files.add(_TreeFile(parts.last, note));
  }
}

class _TreeFile extends _TreeNode {
  const _TreeFile(super.name, this.note);

  final Note note;
}
