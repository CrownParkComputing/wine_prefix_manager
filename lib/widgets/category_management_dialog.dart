import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/category_service.dart';

class CategoryManagementDialog extends StatefulWidget {
  const CategoryManagementDialog({super.key});

  @override
  State<CategoryManagementDialog> createState() => _CategoryManagementDialogState();
}

class _CategoryManagementDialogState extends State<CategoryManagementDialog> {
  List<GameCategory> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  void _loadCategories() {
    setState(() {
      _categories = CategoryService.getAllCategories();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    'Category Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // Toolbar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _showCreateCategoryDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Category'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _resetToDefaults,
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to Defaults'),
                  ),
                ],
              ),
            ),

            // Category list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _categories.isEmpty
                      ? const Center(
                          child: Text(
                            'No categories available',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _categories.length,
                          onReorder: _reorderCategories,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            return _buildCategoryTile(category, index);
                          },
                        ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(GameCategory category, int index) {
    final color = _parseColor(category.color);
    
    return Card(
      key: ValueKey(category.id),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  category.icon,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(category.description),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category.isDefault)
              const Chip(
                label: Text('Default', style: TextStyle(fontSize: 12)),
                backgroundColor: Colors.blue,
                labelStyle: TextStyle(color: Colors.white),
              ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _showEditCategoryDialog(category),
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Category',
            ),
            if (!category.isDefault)
              IconButton(
                onPressed: () => _deleteCategory(category),
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Delete Category',
              ),
          ],
        ),
      ),
    );
  }

  void _reorderCategories(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    
    final reorderedCategories = List<GameCategory>.from(_categories);
    final item = reorderedCategories.removeAt(oldIndex);
    reorderedCategories.insert(newIndex, item);
    
    final categoryIds = reorderedCategories.map((cat) => cat.id).toList();
    
    CategoryService.reorderCategories(categoryIds).then((success) {
      if (success) {
        setState(() {
          _categories = reorderedCategories;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reorder categories')),
        );
      }
    });
  }

  void _showCreateCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => CategoryEditDialog(
        onSaved: (name, description, color, icon) async {
          final success = await CategoryService.createCategory(
            name: name,
            description: description,
            color: color,
            icon: icon,
          );
          
          if (success) {
            _loadCategories();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Category "$name" created successfully')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to create category. Name may already exist.')),
              );
            }
          }
        },
      ),
    );
  }

  void _showEditCategoryDialog(GameCategory category) {
    showDialog(
      context: context,
      builder: (context) => CategoryEditDialog(
        category: category,
        onSaved: (name, description, color, icon) async {
          final success = await CategoryService.updateCategory(
            category.id,
            name: name,
            description: description,
            color: color,
            icon: icon,
          );
          
          if (success) {
            _loadCategories();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Category "$name" updated successfully')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to update category')),
              );
            }
          }
        },
      ),
    );
  }

  void _deleteCategory(GameCategory category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "${category.name}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              final success = await CategoryService.deleteCategory(category.id);
              if (success) {
                _loadCategories();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Category "${category.name}" deleted')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to delete category')),
                  );
                }
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

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will reset all categories to the default set and remove any custom categories you have created.\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              await CategoryService.resetToDefaults();
              _loadCategories();
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Categories reset to defaults')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.blue;
    }
  }
}

class CategoryEditDialog extends StatefulWidget {
  final GameCategory? category;
  final Function(String name, String description, String color, String icon) onSaved;

  const CategoryEditDialog({
    super.key,
    this.category,
    required this.onSaved,
  });

  @override
  State<CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<CategoryEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late String _selectedColor;
  late String _selectedIcon;
  final _formKey = GlobalKey<FormState>();

  static const List<String> _availableColors = [
    '#F44336', '#E91E63', '#9C27B0', '#673AB7', '#3F51B5',
    '#2196F3', '#03A9F4', '#00BCD4', '#009688', '#4CAF50',
    '#8BC34A', '#CDDC39', '#FFEB3B', '#FFC107', '#FF9800',
    '#FF5722', '#795548', '#9E9E9E', '#607D8B'
  ];

  static const List<String> _availableIcons = [
    '🎮', '⚔️', '🗺️', '🧙', '🧠', '🏗️', '⚽', '🏎️', '🧩', '💎',
    '🎯', '🎲', '🎪', '🎨', '🎸', '🎬', '📱', '💻', '🔮', '🌟',
    '🚀', '🏆', '⭐', '🔥', '💡', '🎊', '🎉', '🌈', '🦄', '👑'
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _descriptionController = TextEditingController(text: widget.category?.description ?? '');
    _selectedColor = widget.category?.color ?? '#2196F3';
    _selectedIcon = widget.category?.icon ?? '🎮';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.category != null;
    
    return AlertDialog(
      title: Text(isEdit ? 'Edit Category' : 'Create Category'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a category name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Color selection
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Color:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableColors.map((color) {
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _parseColor(color),
                        borderRadius: BorderRadius.circular(6),
                        border: isSelected 
                            ? Border.all(color: Colors.black, width: 2)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Icon selection
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Icon:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableIcons.map((icon) {
                  final isSelected = icon == _selectedIcon;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = icon),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? _parseColor(_selectedColor) : Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                        border: isSelected 
                            ? Border.all(color: Colors.black, width: 2)
                            : Border.all(color: Colors.grey[300]!),
                      ),
                      child: Center(
                        child: Text(icon, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      widget.onSaved(
        _nameController.text.trim(),
        _descriptionController.text.trim(),
        _selectedColor,
        _selectedIcon,
      );
      Navigator.of(context).pop();
    }
  }

  Color _parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.blue;
    }
  }
}