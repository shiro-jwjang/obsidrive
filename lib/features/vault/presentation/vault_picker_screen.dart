import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/vault_models.dart';
import '../domain/vault_provider.dart';

class VaultPickerScreen extends ConsumerStatefulWidget {
  const VaultPickerScreen({super.key});

  @override
  ConsumerState<VaultPickerScreen> createState() => _VaultPickerScreenState();
}

class _VaultPickerScreenState extends ConsumerState<VaultPickerScreen> {
  static const _rootFolderId = 'root';

  final _folderStack = <DriveFolder>[
    const DriveFolder(id: _rootFolderId, name: '내 드라이브'),
  ];
  late Future<List<DriveFolder>> _foldersFuture;
  DriveFolder? _selectedFolder;

  @override
  void initState() {
    super.initState();
    _foldersFuture = _loadFolders(_rootFolderId);
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(scanProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('볼트 폴더 선택'),
        leading: _folderStack.length > 1
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack)
            : null,
      ),
      body: Column(
        children: <Widget>[
          _CurrentFolder(folder: _folderStack.last),
          Expanded(
            child: FutureBuilder<List<DriveFolder>>(
              future: _foldersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('폴더를 불러오지 못했습니다.\n${snapshot.error}'),
                    ),
                  );
                }

                final folders = snapshot.data ?? const <DriveFolder>[];
                if (folders.isEmpty) {
                  return const Center(child: Text('하위 폴더가 없습니다.'));
                }

                return ListView.builder(
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final selected = folder.id == _selectedFolder?.id;
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder.name),
                      selected: selected,
                      onTap: () {
                        setState(() {
                          _selectedFolder = folder;
                        });
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: '폴더 열기',
                        onPressed: () => _openFolder(folder),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _ScanProgressView(progress: progress),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _selectedFolder == null ||
                        progress.status == ScanStatus.syncing
                    ? null
                    : () => _selectVault(_selectedFolder!),
                child: const Text('이 폴더를 볼트로 사용'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<DriveFolder>> _loadFolders(String parentId) {
    return ref.read(driveFolderServiceProvider).listFolders(parentId);
  }

  void _openFolder(DriveFolder folder) {
    setState(() {
      _folderStack.add(folder);
      _selectedFolder = null;
      _foldersFuture = _loadFolders(folder.id);
    });
  }

  void _goBack() {
    setState(() {
      _folderStack.removeLast();
      _selectedFolder = null;
      _foldersFuture = _loadFolders(_folderStack.last.id);
    });
  }

  Future<void> _selectVault(DriveFolder folder) async {
    await ref.read(vaultScannerProvider).scanAndSyncVault(folder);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('볼트 스캔이 완료되었습니다.')));
    }
  }
}

class _CurrentFolder extends StatelessWidget {
  const _CurrentFolder({required this.folder});

  final DriveFolder folder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.drive_folder_upload_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              folder.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanProgressView extends StatelessWidget {
  const _ScanProgressView({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    if (progress.status == ScanStatus.idle) {
      return const SizedBox.shrink();
    }

    final text = switch (progress.status) {
      ScanStatus.syncing =>
        '스캔 중 ${progress.syncedFiles}/${progress.totalFiles}',
      ScanStatus.complete => '스캔 완료 ${progress.syncedFiles}개',
      ScanStatus.error => progress.lastError ?? '스캔 중 오류가 발생했습니다.',
      ScanStatus.idle => '',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          if (progress.status == ScanStatus.syncing) ...<Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
