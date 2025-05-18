import 'dart:io';
import 'package:dio/dio.dart';
import 'package:process_run/shell.dart';
import '../models/settings.dart';
import '../models/wine_build.dart';
import '../models/prefix_models.dart';
import 'log_service.dart';
import 'wine_prefix_creation_service.dart';
import 'proton_prefix_creation_service.dart';

typedef StatusCallback = void Function(String status);
typedef ProgressCallback = void Function(double progress); // Progress 0.0 to 1.0

/// Main prefix creation service that delegates to specialized services based on prefix type
class PrefixCreationService {
  final Dio _dio = Dio();
  final Shell _shell = Shell(verbose: false);
  final LogService _logService = LogService();
  
  // Specialized services
  final WinePrefixCreationService _wineService = WinePrefixCreationService();
  final ProtonPrefixCreationService _protonService = ProtonPrefixCreationService();

  /// Creates a prefix of the specified type
  Future<WinePrefix?> downloadAndCreatePrefix({
    required BaseBuild? selectedBuild,
    required String prefixName,
    required Settings settings,
    required PrefixType prefixType,
    required StatusCallback onStatusUpdate,
    required ProgressCallback onProgressUpdate,
  }) async {
    // Log what we're doing
    _logService.log('Creating ${prefixType.name} prefix: $prefixName');
    
    // Delegate to the appropriate specialized service based on prefix type
    switch (prefixType) {
      case PrefixType.wine:
        return _wineService.createWinePrefix(
          selectedBuild: selectedBuild,
          prefixName: prefixName,
          settings: settings,
          onStatusUpdate: onStatusUpdate,
          onProgressUpdate: onProgressUpdate,
        );
        
      case PrefixType.proton:
        return _protonService.createProtonPrefix(
          selectedBuild: selectedBuild,
          prefixName: prefixName,
          settings: settings,
          onStatusUpdate: onStatusUpdate,
          onProgressUpdate: onProgressUpdate,
        );
    }
  }
} 