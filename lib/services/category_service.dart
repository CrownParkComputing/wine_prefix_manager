import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class GameCategory {
  final String id;
  final String name;
  final String description;
  final String color; // Hex color code
  final String icon; // Icon name or emoji
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDefault;

  const GameCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.isDefault = false,
  });

  factory GameCategory.fromJson(Map<String, dynamic> json) {
    return GameCategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      color: json['color'] ?? '#2196F3',
      icon: json['icon'] ?? '🎮',
      sortOrder: json['sortOrder'] ?? 0,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
      isDefault: json['isDefault'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDefault': isDefault,
    };
  }

  GameCategory copyWith({
    String? id,
    String? name,
    String? description,
    String? color,
    String? icon,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDefault,
  }) {
    return GameCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameCategory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class CategoryService {
  static const String _categoriesFileName = 'game_categories.json';
  static String? _categoriesFilePath;
  static List<GameCategory> _categories = [];
  static bool _initialized = false;

  /// Initialize the category service with the settings directory
  static Future<void> initialize(String settingsDirectory) async {
    _categoriesFilePath = p.join(settingsDirectory, _categoriesFileName);
    await _loadCategories();
    _initialized = true;
  }

  /// Get all categories sorted by sort order
  static List<GameCategory> getAllCategories() {
    if (!_initialized) {
      print('CategoryService not initialized');
      return _getDefaultCategories();
    }
    
    final categories = List<GameCategory>.from(_categories);
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories;
  }

  /// Get category names only (for backward compatibility)
  static List<String> getCategoryNames() {
    return getAllCategories().map((cat) => cat.name).toList();
  }

  /// Get category by ID
  static GameCategory? getCategoryById(String id) {
    try {
      return _categories.firstWhere((cat) => cat.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get category by name
  static GameCategory? getCategoryByName(String name) {
    try {
      return _categories.firstWhere((cat) => cat.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Create a new category
  static Future<bool> createCategory({
    required String name,
    required String description,
    String color = '#2196F3',
    String icon = '🎮',
    int? sortOrder,
  }) async {
    if (!_initialized) {
      return false;
    }

    // Check if category already exists
    if (_categories.any((cat) => cat.name.toLowerCase() == name.toLowerCase())) {
      return false;
    }

    final now = DateTime.now();
    final newCategory = GameCategory(
      id: _generateId(),
      name: name.trim(),
      description: description.trim(),
      color: color,
      icon: icon,
      sortOrder: sortOrder ?? _getNextSortOrder(),
      createdAt: now,
      updatedAt: now,
    );

    _categories.add(newCategory);
    await _saveCategories();
    return true;
  }

  /// Update an existing category
  static Future<bool> updateCategory(String id, {
    String? name,
    String? description,
    String? color,
    String? icon,
    int? sortOrder,
  }) async {
    if (!_initialized) {
      return false;
    }

    final categoryIndex = _categories.indexWhere((cat) => cat.id == id);
    if (categoryIndex == -1) {
      return false;
    }

    final category = _categories[categoryIndex];
    
    // Check if new name conflicts with existing categories (excluding current)
    if (name != null && name != category.name) {
      if (_categories.any((cat) => cat.id != id && cat.name.toLowerCase() == name.toLowerCase())) {
        return false;
      }
    }

    _categories[categoryIndex] = category.copyWith(
      name: name,
      description: description,
      color: color,
      icon: icon,
      sortOrder: sortOrder,
      updatedAt: DateTime.now(),
    );

    await _saveCategories();
    return true;
  }

  /// Delete a category
  static Future<bool> deleteCategory(String id) async {
    if (!_initialized) {
      return false;
    }

    final category = getCategoryById(id);
    if (category == null) {
      return false;
    }

    if (category.isDefault) {
      return false;
    }

    _categories.removeWhere((cat) => cat.id == id);
    await _saveCategories();
    return true;
  }

  /// Reorder categories
  static Future<bool> reorderCategories(List<String> categoryIds) async {
    if (!_initialized) {
      return false;
    }

    try {
      for (int i = 0; i < categoryIds.length; i++) {
        final categoryIndex = _categories.indexWhere((cat) => cat.id == categoryIds[i]);
        if (categoryIndex != -1) {
          _categories[categoryIndex] = _categories[categoryIndex].copyWith(
            sortOrder: i,
            updatedAt: DateTime.now(),
          );
        }
      }

      await _saveCategories();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Import categories from old string list format
  static Future<void> importFromStringList(List<String> categoryNames) async {
    if (!_initialized) return;

    for (int i = 0; i < categoryNames.length; i++) {
      final name = categoryNames[i];
      if (!_categories.any((cat) => cat.name == name)) {
        final now = DateTime.now();
        _categories.add(GameCategory(
          id: _generateId(),
          name: name,
          description: 'Imported category',
          color: _getRandomColor(),
          icon: _getRandomIcon(),
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }
    
    await _saveCategories();
  }

  /// Reset to default categories
  static Future<void> resetToDefaults() async {
    if (!_initialized) return;

    _categories.clear();
    _categories.addAll(_getDefaultCategories());
    await _saveCategories();
  }

  // Private methods

  static Future<void> _loadCategories() async {
    try {
      final file = File(_categoriesFilePath!);
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonData = json.decode(content) as Map<String, dynamic>;
        final categoriesList = jsonData['categories'] as List<dynamic>;
        
        _categories = categoriesList
            .map((catJson) => GameCategory.fromJson(catJson))
            .toList();
        
      } else {
        _categories = _getDefaultCategories();
        await _saveCategories();
      }
    } catch (e) {
      _categories = _getDefaultCategories();
    }
  }

  static Future<void> _saveCategories() async {
    try {
      final file = File(_categoriesFilePath!);
      await file.parent.create(recursive: true);
      
      final data = {
        'categories': _categories.map((cat) => cat.toJson()).toList(),
        'version': 1,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      await file.writeAsString(json.encode(data));
    } catch (e) {
    }
  }

  static List<GameCategory> _getDefaultCategories() {
    final now = DateTime.now();
    return [
      GameCategory(
        id: 'action',
        name: 'Action',
        description: 'Fast-paced games with combat and challenges',
        color: '#F44336',
        icon: '⚔️',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'adventure',
        name: 'Adventure',
        description: 'Story-driven exploration games',
        color: '#4CAF50',
        icon: '🗺️',
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'rpg',
        name: 'RPG',
        description: 'Role-playing games with character progression',
        color: '#9C27B0',
        icon: '🧙',
        sortOrder: 2,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'strategy',
        name: 'Strategy',
        description: 'Tactical and strategic thinking games',
        color: '#FF9800',
        icon: '🧠',
        sortOrder: 3,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'simulation',
        name: 'Simulation',
        description: 'Life and world simulation games',
        color: '#2196F3',
        icon: '🏗️',
        sortOrder: 4,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'sports',
        name: 'Sports',
        description: 'Athletic and competitive sports games',
        color: '#795548',
        icon: '⚽',
        sortOrder: 5,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'racing',
        name: 'Racing',
        description: 'Vehicle racing and driving games',
        color: '#607D8B',
        icon: '🏎️',
        sortOrder: 6,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'puzzle',
        name: 'Puzzle',
        description: 'Brain teasers and logic games',
        color: '#E91E63',
        icon: '🧩',
        sortOrder: 7,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'indie',
        name: 'Indie',
        description: 'Independent developer games',
        color: '#00BCD4',
        icon: '💎',
        sortOrder: 8,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
      GameCategory(
        id: 'uncategorized',
        name: 'Uncategorized',
        description: 'Games without assigned categories',
        color: '#9E9E9E',
        icon: '📦',
        sortOrder: 99,
        createdAt: now,
        updatedAt: now,
        isDefault: true,
      ),
    ];
  }

  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  static int _getNextSortOrder() {
    if (_categories.isEmpty) return 0;
    return _categories.map((cat) => cat.sortOrder).reduce((max, order) => order > max ? order : max) + 1;
  }

  static String _getRandomColor() {
    final colors = [
      '#F44336', '#E91E63', '#9C27B0', '#673AB7', '#3F51B5',
      '#2196F3', '#03A9F4', '#00BCD4', '#009688', '#4CAF50',
      '#8BC34A', '#CDDC39', '#FFEB3B', '#FFC107', '#FF9800',
      '#FF5722', '#795548', '#9E9E9E', '#607D8B'
    ];
    return colors[DateTime.now().millisecondsSinceEpoch % colors.length];
  }

  static String _getRandomIcon() {
    final icons = ['🎮', '🎯', '🎲', '🎪', '🎨', '🎸', '🎬', '📱', '💻', '🔮'];
    return icons[DateTime.now().millisecondsSinceEpoch % icons.length];
  }
}