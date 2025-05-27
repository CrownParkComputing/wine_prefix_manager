import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../providers/settings_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class GameSettingsModal extends StatefulWidget {
  final GameEntry game;
  final Function(GameEntry, String?) onSaveLaunchOptions;
  final Function(GameEntry, String?) onChangeCategory;
  final Function(GameEntry, bool) onToggleWorkingStatus;
  final Function(GameEntry)? onDelete;
  final Function(GameEntry, ExeEntry)? onUpdateCompressedGame;

  const GameSettingsModal({
    super.key,
    required this.game,
    required this.onSaveLaunchOptions,
    required this.onChangeCategory,
    required this.onToggleWorkingStatus,
    this.onDelete,
    this.onUpdateCompressedGame,
  });

  @override
  State<GameSettingsModal> createState() => _GameSettingsModalState();
}

class _GameSettingsModalState extends State<GameSettingsModal> {
  late TextEditingController _launchOptionsController;
  String? _selectedCategory;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _launchOptionsController = TextEditingController(
      text: widget.game.exe.launchOptions ?? '',
    );
    _selectedCategory = widget.game.exe.category;
    
    // Listen for changes
    _launchOptionsController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _launchOptionsController.removeListener(_onTextChanged);
    _launchOptionsController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasChanges = true;
    });
  }

  void _saveChanges() {
    // Save launch options
    widget.onSaveLaunchOptions(
      widget.game,
      _launchOptionsController.text.isEmpty ? null : _launchOptionsController.text,
    );
    
    setState(() {
      _hasChanges = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.game.exe.isCompressed ? 'Compressed ' : ''}Game'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete "${widget.game.exe.name}"?'),
            const SizedBox(height: 8),
            Text(
              widget.game.exe.isCompressed 
                ? 'This will remove the game from your library. The original archive file will not be deleted.'
                : 'This will remove the game from your library. The game files on disk will not be deleted.',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close confirmation dialog
              Navigator.of(context).pop(); // Close settings modal
              if (widget.onDelete != null) {
                widget.onDelete!(widget.game);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Methods for compressed game settings
  Future<void> _selectExtractPath() async {
    final selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Extract Location',
      initialDirectory: widget.game.exe.extractedBasePath,
    );

    if (selectedDir != null && widget.onUpdateCompressedGame != null) {
      final updatedExe = widget.game.exe.copyWith(
        extractedBasePath: selectedDir,
      );
      widget.onUpdateCompressedGame!(widget.game, updatedExe);
      setState(() {}); // Trigger rebuild to show new path
    }
  }

  Future<void> _addSaveDataPath() async {
    final selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Save Data Folder',
    );

    if (selectedDir != null && widget.onUpdateCompressedGame != null) {
      final currentPaths = List<String>.from(widget.game.exe.saveDataPaths);
      if (!currentPaths.contains(selectedDir)) {
        currentPaths.add(selectedDir);
        final updatedExe = widget.game.exe.copyWith(
          saveDataPaths: currentPaths,
        );
        widget.onUpdateCompressedGame!(widget.game, updatedExe);
        setState(() {}); // Trigger rebuild to show new path
      }
    }
  }

  void _removeSaveDataPath(int index) {
    if (widget.onUpdateCompressedGame != null) {
      final currentPaths = List<String>.from(widget.game.exe.saveDataPaths);
      if (index >= 0 && index < currentPaths.length) {
        currentPaths.removeAt(index);
        final updatedExe = widget.game.exe.copyWith(
          saveDataPaths: currentPaths,
        );
        widget.onUpdateCompressedGame!(widget.game, updatedExe);
        setState(() {}); // Trigger rebuild to show updated list
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.5,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Settings - ${widget.game.exe.name}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Launch Options
                    _buildSettingsCard('Launch Options', [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Additional command line arguments:',
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _launchOptionsController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'e.g., --windowed --resolution 1920x1080',
                              ),
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                    ]),
                    
                    const SizedBox(height: 16),
                    
                    // Category
                    _buildSettingsCard('Category', [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Consumer<SettingsProvider>(
                          builder: (context, settingsProvider, child) {
                            final categories = settingsProvider.settings.categories;
                            return DropdownButtonFormField<String?>(
                              value: _selectedCategory,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Game Category',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Uncategorized'),
                                ),
                                ...categories.map((category) => DropdownMenuItem<String?>(
                                  value: category,
                                  child: Text(category),
                                )),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedCategory = value;
                                });
                                widget.onChangeCategory(widget.game, value);
                              },
                            );
                          },
                        ),
                      ),
                    ]),
                    
                    const SizedBox(height: 16),
                    
                    // Working Status
                    _buildSettingsCard('Game Status', [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SwitchListTile(
                          title: const Text('Game is working'),
                          subtitle: Text(widget.game.exe.notWorking 
                              ? 'Marked as not working' 
                              : 'Marked as working'),
                          value: !widget.game.exe.notWorking,
                          onChanged: (value) {
                            widget.onToggleWorkingStatus(widget.game, !value);
                            setState(() {}); // Trigger rebuild to update subtitle
                          },
                        ),
                      ),
                    ]),
                    
                    const SizedBox(height: 16),
                    
                    // Compressed Game Settings (only show for compressed games)
                    if (widget.game.exe.isCompressed) ...[
                      _buildSettingsCard('Compressed Game Settings', [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Extract folder setting
                              Text(
                                'Extract Location:',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Theme.of(context).dividerColor),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        widget.game.exe.extractedBasePath ?? 'Not set',
                                        style: const TextStyle(fontFamily: 'monospace'),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.folder_open),
                                    label: const Text('Change'),
                                    onPressed: () => _selectExtractPath(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              // Archive path (read-only)
                              Text(
                                'Archive File:',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).dividerColor),
                                  borderRadius: BorderRadius.circular(4),
                                  color: Colors.grey.withOpacity(0.1),
                                ),
                                child: Text(
                                  widget.game.exe.compressedArchivePath ?? 'Unknown',
                                  style: const TextStyle(fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // Save data paths
                              Text(
                                'Save Data Folders:',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Additional folders to include when backing up this game.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              
                              // List of save data paths
                              if (widget.game.exe.saveDataPaths.isNotEmpty) ...[
                                ...widget.game.exe.saveDataPaths.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final path = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Theme.of(context).dividerColor),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              path,
                                              style: const TextStyle(fontFamily: 'monospace'),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 20),
                                          onPressed: () => _removeSaveDataPath(index),
                                          tooltip: 'Remove save data path',
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ] else ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Theme.of(context).dividerColor),
                                    borderRadius: BorderRadius.circular(4),
                                    color: Colors.grey.withOpacity(0.05),
                                  ),
                                  child: const Text(
                                    'No save data folders configured',
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                              
                              const SizedBox(height: 8),
                              
                              // Add save data path button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Save Data Folder'),
                                  onPressed: () => _addSaveDataPath(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      
                      const SizedBox(height: 16),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    // Prefix Information
                    _buildSettingsCard('Prefix Information', [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow('Current Prefix', widget.game.prefix.name),
                            _buildInfoRow('Architecture', widget.game.prefix.architecture),
                            _buildInfoRow('Type', widget.game.prefix.type == PrefixType.wine ? 'Wine' : 'Proton'),
                            if (widget.game.exe.isCompressed)
                              _buildInfoRow('Game Type', 'Compressed Game'),
                            const SizedBox(height: 12),
                            
                            // Action buttons
                            Row(
                              children: [
                                // Delete button for all games
                                if (widget.onDelete != null)
                                  ElevatedButton.icon(
                                    onPressed: () => _showDeleteConfirmation(),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Delete Game'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            
            // Action buttons
            const Divider(),
            Row(
              children: [
                const Spacer(),
                if (_hasChanges) ...[
                  TextButton(
                    onPressed: () {
                      // Reset changes
                      _launchOptionsController.text = widget.game.exe.launchOptions ?? '';
                      setState(() {
                        _hasChanges = false;
                      });
                    },
                    child: const Text('Reset'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _saveChanges,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(String title, List<Widget> children) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
} 