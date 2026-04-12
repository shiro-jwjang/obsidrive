import 'package:flutter/material.dart';

import '../domain/vault_models.dart';

class FolderTreeWidget extends StatelessWidget {
  const FolderTreeWidget({super.key, required this.notes});

  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    final root = _TreeFolder('');
    for (final note in notes.where((note) => _isMarkdownPath(note.filePath))) {
      root.add(note);
    }

    final children = root.sortedChildren;
    if (children.isEmpty) {
      return const Center(child: Text('표시할 마크다운 파일이 없습니다.'));
    }

    return ListView(
      children: <Widget>[
        for (final child in children) _TreeNodeTile(node: child, depth: 0),
      ],
    );
  }

  static bool _isMarkdownPath(String path) {
    return path.toLowerCase().endsWith('.md');
  }
}

class _TreeNodeTile extends StatelessWidget {
  const _TreeNodeTile({required this.node, required this.depth});

  final _TreeNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    if (node is _TreeFolder) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('folder:${node.path}'),
          leading: const Icon(Icons.folder_outlined),
          tilePadding: EdgeInsets.only(left: 16 + depth * 20, right: 16),
          childrenPadding: EdgeInsets.zero,
          title: Text(node.name),
          children: <Widget>[
            for (final child in node.sortedChildren)
              _TreeNodeTile(node: child, depth: depth + 1),
          ],
        ),
      );
    }

    final file = node as _TreeFile;
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      contentPadding: EdgeInsets.only(left: 16 + depth * 20, right: 16),
      title: Text(file.name),
      onTap: () {
        Navigator.of(context).pushNamed('/reader', arguments: file.note);
      },
    );
  }
}

sealed class _TreeNode {
  const _TreeNode(this.name);

  final String name;
}

class _TreeFolder extends _TreeNode {
  _TreeFolder(super.name);

  final folders = <String, _TreeFolder>{};
  final files = <_TreeFile>[];

  String get path => name;

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
      folder = folder.folders.putIfAbsent(part, () => _TreeFolder(part));
    }

    folder.files.add(_TreeFile(parts.last, note));
  }
}

class _TreeFile extends _TreeNode {
  const _TreeFile(super.name, this.note);

  final Note note;
}
