import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/prefix_provider.dart';
import 'enhanced_file_manager_page.dart';
import 'backup_manager_page.dart';

class FilesAndBackupPage extends StatefulWidget {
  const FilesAndBackupPage({super.key});

  @override
  State<FilesAndBackupPage> createState() => _FilesAndBackupPageState();
}

class _FilesAndBackupPageState extends State<FilesAndBackupPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files & Backup'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha:0.6),
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(
              icon: Icon(Icons.folder_copy_outlined),
              text: 'File Manager',
            ),
            Tab(
              icon: Icon(Icons.backup_outlined),
              text: 'Backup Manager',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFileManagerTab(),
          _buildBackupManagerTab(),
        ],
      ),
    );
  }

  Widget _buildFileManagerTab() {
    return Consumer<PrefixProvider>(
      builder: (context, prefixProvider, child) {
        final games = prefixProvider.getAllGamesFromPrefixes();
        return EnhancedFileManagerPage(
          game: games.isNotEmpty ? games.first : null,
        );
      },
    );
  }

  Widget _buildBackupManagerTab() {
    return const BackupManagerPage();
  }
} 