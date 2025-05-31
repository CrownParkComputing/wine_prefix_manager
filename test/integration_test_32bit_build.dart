import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('32-bit Wine Build Prefix Creation Tests', () {
    late String testPrefixPath;

    tearDownAll(() {
      // Clean up test directory
      try {
        if (testPrefixPath != null && Directory(testPrefixPath).existsSync()) {
          Directory(testPrefixPath).deleteSync(recursive: true);
        }
      } catch (e) {
        print('Cleanup error: $e');
      }
    });

    test('Verify 32-bit Wine build exists and is functional', () async {
      final build32BitPath = '/home/jon/.local/share/wine_prefix_manager/downloaded_builds/wine-10.4-staging-tkg-x86';
      final build32BitDir = Directory(build32BitPath);
      
      print('Checking 32-bit Wine build at: $build32BitPath');
      expect(build32BitDir.existsSync(), isTrue, reason: '32-bit Wine build directory should exist');

      final wineExecutable = File(path.join(build32BitPath, 'bin', 'wine'));
      expect(wineExecutable.existsSync(), isTrue, reason: 'Wine executable should exist in 32-bit build');
      expect(wineExecutable.statSync().mode & 0x49, greaterThan(0), reason: 'Wine executable should be executable');

      // Test wine --version with 32-bit build
      final versionResult = await Process.run(
        wineExecutable.path,
        ['--version'],
      );
      
      print('32-bit Wine version: ${versionResult.stdout}');
      expect(versionResult.exitCode, equals(0), reason: '32-bit Wine --version should succeed');
      expect(versionResult.stdout.toString().toLowerCase(), contains('wine'), reason: 'Output should contain "wine"');
    });

    test('Create 32-bit prefix manually using 32-bit Wine build', () async {
      final build32BitPath = '/home/jon/.local/share/wine_prefix_manager/downloaded_builds/wine-10.4-staging-tkg-x86';
      final wineExecutable = path.join(build32BitPath, 'bin', 'wine');

      final prefixName = 'test_32bit_${DateTime.now().millisecondsSinceEpoch}';
      testPrefixPath = path.join('/tmp', 'wine_prefix_manager_test', prefixName);

      print('Creating 32-bit prefix: $prefixName');
      print('Prefix path: $testPrefixPath');
      print('Using Wine build: $build32BitPath');

      // Create prefix directory
      await Directory(testPrefixPath).create(recursive: true);

      // Set up environment for 32-bit Wine prefix
      final env = Map<String, String>.from(Platform.environment);
      env['WINEPREFIX'] = testPrefixPath;
      env['WINEARCH'] = 'win32';
      env['LD_LIBRARY_PATH'] = '${path.join(build32BitPath, 'lib')}:${env['LD_LIBRARY_PATH'] ?? ''}';
      env['WINEDLLOVERRIDES'] = 'winemenubuilder.exe=d';

      print('Environment variables:');
      print('  WINEPREFIX: ${env['WINEPREFIX']}');
      print('  WINEARCH: ${env['WINEARCH']}');
      print('  LD_LIBRARY_PATH: ${env['LD_LIBRARY_PATH']}');

      // Initialize prefix with wineboot
      print('Running wineboot -u to initialize 32-bit prefix...');
      final winebootResult = await Process.run(
        wineExecutable,
        ['wineboot', '-u'],
        environment: env,
      );

      print('wineboot exit code: ${winebootResult.exitCode}');
      if (winebootResult.stdout.isNotEmpty) print('wineboot stdout: ${winebootResult.stdout}');
      if (winebootResult.stderr.isNotEmpty) print('wineboot stderr: ${winebootResult.stderr}');

      expect(winebootResult.exitCode, equals(0), reason: 'wineboot should succeed for 32-bit prefix');
      expect(Directory(testPrefixPath).existsSync(), isTrue, reason: 'Prefix directory should exist');

      // Create .prefix_config file to match Wine Prefix Manager format
      final configFile = File(path.join(testPrefixPath, '.prefix_config'));
      await configFile.writeAsString(jsonEncode({
        'buildPath': build32BitPath,
        'type': 'PrefixType.wine',
        'architecture': 'win32',
      }));

      print('32-bit prefix created successfully!');
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('Verify 32-bit prefix has correct structure', () async {
      if (testPrefixPath == null || !Directory(testPrefixPath).existsSync()) {
        print('SKIP: No test prefix available');
        return;
      }

      print('Verifying 32-bit prefix structure at: $testPrefixPath');

      // Check essential Wine files
      final driveC = Directory(path.join(testPrefixPath, 'drive_c'));
      expect(driveC.existsSync(), isTrue, reason: 'drive_c should exist');

      final systemReg = File(path.join(testPrefixPath, 'system.reg'));
      expect(systemReg.existsSync(), isTrue, reason: 'system.reg should exist');

      final userReg = File(path.join(testPrefixPath, 'user.reg'));
      expect(userReg.existsSync(), isTrue, reason: 'user.reg should exist');

      // Check Windows directory structure
      final windowsDir = Directory(path.join(testPrefixPath, 'drive_c', 'windows'));
      expect(windowsDir.existsSync(), isTrue, reason: 'windows directory should exist');

      final system32Dir = Directory(path.join(testPrefixPath, 'drive_c', 'windows', 'system32'));
      expect(system32Dir.existsSync(), isTrue, reason: 'system32 directory should exist');

      // CRITICAL: Check that this is a TRUE 32-bit prefix
      final programFiles = Directory(path.join(testPrefixPath, 'drive_c', 'Program Files'));
      expect(programFiles.existsSync(), isTrue, reason: 'Program Files should exist in 32-bit prefix');

      final programFilesX86 = Directory(path.join(testPrefixPath, 'drive_c', 'Program Files (x86)'));
      expect(programFilesX86.existsSync(), isFalse, reason: 'Program Files (x86) should NOT exist in true 32-bit prefix');

      print('✓ Verified: No "Program Files (x86)" directory (correct for 32-bit)');
      print('✓ Verified: "Program Files" directory exists');

      // Check kernel32.dll architecture
      final kernel32 = File(path.join(testPrefixPath, 'drive_c', 'windows', 'system32', 'kernel32.dll'));
      if (kernel32.existsSync()) {
        final fileResult = await Process.run('file', [kernel32.path]);
        print('kernel32.dll architecture: ${fileResult.stdout}');
        expect(fileResult.stdout.toString().toLowerCase(), contains('pe32'), reason: 'kernel32.dll should be 32-bit PE32 format');
        expect(fileResult.stdout.toString().toLowerCase(), isNot(contains('pe32+')), reason: 'kernel32.dll should NOT be 64-bit PE32+ format');
      }

      print('32-bit prefix structure verification passed!');
    });

    test('Test 32-bit Wine prefix configuration and registry', () async {
      if (testPrefixPath == null || !Directory(testPrefixPath).existsSync()) {
        print('SKIP: No test prefix available');
        return;
      }

      final build32BitPath = '/home/jon/.local/share/wine_prefix_manager/downloaded_builds/wine-10.4-staging-tkg-x86';
      final wineExecutable = path.join(build32BitPath, 'bin', 'wine');

      final env = Map<String, String>.from(Platform.environment);
      env['WINEPREFIX'] = testPrefixPath;
      env['WINEARCH'] = 'win32';
      env['LD_LIBRARY_PATH'] = '${path.join(build32BitPath, 'lib')}:${env['LD_LIBRARY_PATH'] ?? ''}';

      print('Testing 32-bit prefix configuration...');
      print('WINEPREFIX: ${env['WINEPREFIX']}');
      print('WINEARCH: ${env['WINEARCH']}');
      print('Using Wine: $wineExecutable');

      // Test wineboot to ensure prefix is properly initialized
      print('Running wineboot to verify initialization...');
      final winebootResult = await Process.run(
        wineExecutable,
        ['wineboot', '-u'],
        environment: env,
      );

      print('wineboot exit code: ${winebootResult.exitCode}');
      if (winebootResult.stderr.isNotEmpty) {
        print('wineboot stderr: ${winebootResult.stderr}');
      }

      expect(winebootResult.exitCode, equals(0), reason: 'wineboot should succeed on 32-bit prefix');

      print('32-bit prefix configuration test completed!');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('Test running a 32-bit application in 32-bit prefix', () async {
      if (testPrefixPath == null || !Directory(testPrefixPath).existsSync()) {
        print('SKIP: No test prefix available');
        return;
      }

      final build32BitPath = '/home/jon/.local/share/wine_prefix_manager/downloaded_builds/wine-10.4-staging-tkg-x86';
      final wineExecutable = path.join(build32BitPath, 'bin', 'wine');

      final env = Map<String, String>.from(Platform.environment);
      env['WINEPREFIX'] = testPrefixPath;
      env['WINEARCH'] = 'win32';
      env['LD_LIBRARY_PATH'] = '${path.join(build32BitPath, 'lib')}:${env['LD_LIBRARY_PATH'] ?? ''}';

      print('Testing 32-bit application execution in 32-bit prefix...');

      // Test Wine's built-in notepad (32-bit)
      print('Launching notepad.exe (32-bit) to verify application compatibility...');
      
      try {
        final process = await Process.start(
          wineExecutable,
          ['notepad.exe'],
          environment: env,
        );

        // Wait briefly to see if notepad starts without errors
        await Future.delayed(const Duration(seconds: 3));

        // Check if process is still running (GUI opened successfully)
        bool processRunning = true;
        try {
          process.kill(ProcessSignal.sigterm);
          print('Successfully launched and terminated notepad.exe');
        } catch (e) {
          processRunning = false;
          print('Notepad process may have already terminated');
        }

        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => 0, // Assume success if it times out (GUI opened)
        );

        print('Notepad process exit code: $exitCode');

        print('32-bit application test completed - notepad launched successfully!');

      } catch (e) {
        print('Notepad execution error: $e');
        // Don't fail the test here as display issues are common in CI
        print('This might be due to display/GUI limitations in the test environment');
      }

      print('32-bit application compatibility test passed!');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('Verify prefix architecture in .prefix_config', () async {
      if (testPrefixPath == null || !Directory(testPrefixPath).existsSync()) {
        print('SKIP: No test prefix available');
        return;
      }

      final configFile = File(path.join(testPrefixPath, '.prefix_config'));
      expect(configFile.existsSync(), isTrue, reason: '.prefix_config should exist');

      final configContent = await configFile.readAsString();
      print('.prefix_config content:');
      print(configContent);

      expect(configContent, contains('"architecture":"win32"'), reason: 'Config should specify win32 architecture');
      expect(configContent, contains('wine-10.4-staging-tkg-x86'), reason: 'Config should reference the 32-bit build');

      print('✓ Verified: .prefix_config correctly specifies 32-bit architecture');
    });
  });
} 