import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart';

Future<void> main() async {
  final Shell shell = Shell(verbose: true);
  
  // Define test paths
  final String downloadDir = path.join(Directory.current.absolute.path, "proton_builds");
  final String filePath = path.join(downloadDir, "Kronek-Proton-10.0-1-amd64");
  
  print('Testing extraction of Kronek Proton');
  print('Current directory: ${Directory.current.absolute.path}');
  
  // Ensure the directory exists
  if (!await Directory(downloadDir).exists()) {
    await Directory(downloadDir).create(recursive: true);
    print('Created download directory: $downloadDir');
  }
  
  // Get a list of current directories before extraction
  final List<FileSystemEntity> beforeDirs = await Directory(downloadDir)
      .list()
      .where((entity) => entity is Directory)
      .toList();
  
  print('Directories before extraction: ${beforeDirs.map((e) => e.path).join(', ')}');
  
  // Run tar extraction if the file exists
  if (await File('$filePath.tar.xz').exists()) {
    print('Extracting "$filePath.tar.xz" to "$downloadDir"...');
    
    final result = await shell.run('tar -xvf "$filePath.tar.xz" -C "$downloadDir"');
    print('Extraction output: ${result.outText}');
    print('Extraction complete.');
    
    // Get list of directories after extraction and find new ones
    final List<FileSystemEntity> afterDirs = await Directory(downloadDir)
        .list()
        .where((entity) => entity is Directory)
        .toList();
    
    print('Directories after extraction: ${afterDirs.map((e) => e.path).join(', ')}');
    
    final List<FileSystemEntity> newDirs = afterDirs
        .where((after) => !beforeDirs.any((before) => before.path == after.path))
        .toList();
    
    if (newDirs.isNotEmpty) {
      print('Found new extracted directory: ${newDirs.first.path}');
    } else {
      print('No new directories found after extraction');
      
      // Try to determine directory name from the extraction output
      final RegExp dirRegex = RegExp(r'^([^/]+)/');
      final match = dirRegex.firstMatch(result.outText.split('\n').firstWhere(
        (line) => line.contains('/'), 
        orElse: () => ''
      ));
      
      if (match != null && match.groupCount >= 1) {
        final String detectedDirName = match.group(1) ?? '';
        if (detectedDirName.isNotEmpty) {
          print('Detected directory from extraction output: ${path.join(downloadDir, detectedDirName)}');
        }
      }
      
      // Last resort: look for any directory containing "proton" in the name
      final List<FileSystemEntity> protonDirs = afterDirs
          .where((dir) => path.basename(dir.path).toLowerCase().contains('proton'))
          .toList();
      
      if (protonDirs.isNotEmpty) {
        print('Found proton directory: ${protonDirs.first.path}');
      }
    }
  } else {
    print('File not found: $filePath.tar.xz');
    
    // List all files in the directory
    final List<FileSystemEntity> files = await Directory(downloadDir).list().toList();
    print('Files in directory: ${files.map((e) => e.path).join(', ')}');
  }
} 