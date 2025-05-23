import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/prefix_models.dart';
import '../providers/settings_provider.dart';

class GameSettingsModal extends StatefulWidget {
  final GameEntry game;
  final Function(GameEntry, String?) onSaveLaunchOptions;
  final Function(GameEntry, String?) onChangeCategory;
  final Function(GameEntry, bool) onToggleWorkingStatus;
  final Function(GameEntry)? onChangePrefix;

  const GameSettingsModal({
    super.key,
    required this.game,
    required this.onSaveLaunchOptions,
    required this.onChangeCategory,
    required this.onToggleWorkingStatus,
    this.onChangePrefix,
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
                            const SizedBox(height: 12),
                            if (widget.onChangePrefix != null)
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onChangePrefix!(widget.game);
                                },
                                icon: const Icon(Icons.swap_horiz),
                                label: const Text('Change Prefix'),
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