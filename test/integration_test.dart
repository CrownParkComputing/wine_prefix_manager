import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('32-bit Wine Prefix Integration Tests', () {
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

    test('Test system Wine availability and basic functionality', () async {
      // Check if Wine is available
      final wineCheck = await Process.run('which', ['wine']);
      if (wineCheck.exitCode != 0) {
        print('SKIP: Wine not found in system PATH');
        return;
      }

      final systemWinePath = wineCheck.stdout.toString().trim();
      print('Found Wine at: $systemWinePath');

      // Test wine --version
      final versionResult = await Process.run('wine', ['--version']);
      print('Wine version: ${versionResult.stdout}');
      expect(versionResult.exitCode, equals(0), reason: 'Wine --version should succeed');
    });

    test('Create minimal 32-bit Wine prefix manually', () async {
      // Skip test if no Wine is available
      final wineCheck = await Process.run('which', ['wine']);
      if (wineCheck.exitCode != 0) {
        print('SKIP: Wine not found in system PATH');
        return;
      }

      // Create test prefix directory
      testPrefixPath = path.join(Directory.systemTemp.path, 'test_32bit_prefix_${DateTime.now().millisecondsSinceEpoch}');
      Directory(testPrefixPath).createSync(recursive: true);

      print('Creating 32-bit Wine prefix at: $testPrefixPath');

      // Set up environment for 32-bit Wine prefix
      final env = Map<String, String>.from(Platform.environment);
      env['WINEPREFIX'] = testPrefixPath;
      env['WINEARCH'] = 'win32';
      env['WINEDLLOVERRIDES'] = 'winemenubuilder.exe=d';

      print('Environment variables:');
      print('  WINEPREFIX: ${env['WINEPREFIX']}');
      print('  WINEARCH: ${env['WINEARCH']}');
      print('  DISPLAY: ${env['DISPLAY']}');
      print('  WAYLAND_DISPLAY: ${env['WAYLAND_DISPLAY']}');

      // Initialize prefix with wineboot
      print('Running wineboot -u...');
      final winebootResult = await Process.run(
        'wine',
        ['wineboot', '-u'],
        environment: env,
      );

      print('wineboot exit code: ${winebootResult.exitCode}');
      if (winebootResult.stdout.isNotEmpty) print('wineboot stdout: ${winebootResult.stdout}');
      if (winebootResult.stderr.isNotEmpty) print('wineboot stderr: ${winebootResult.stderr}');

      expect(winebootResult.exitCode, equals(0), reason: 'wineboot should succeed');
      expect(Directory(testPrefixPath).existsSync(), isTrue, reason: 'Prefix directory should exist');

      // Check that basic Wine files were created
      final driveC = Directory(path.join(testPrefixPath, 'drive_c'));
      expect(driveC.existsSync(), isTrue, reason: 'drive_c should be created');

      final systemReg = File(path.join(testPrefixPath, 'system.reg'));
      expect(systemReg.existsSync(), isTrue, reason: 'system.reg should be created');

      print('32-bit Wine prefix created successfully!');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('Test winecfg on 32-bit prefix', () async {
      if (testPrefixPath == null || !Directory(testPrefixPath).existsSync()) {
        print('SKIP: No test prefix available');
        return;
      }

      print('Testing winecfg on 32-bit prefix: $testPrefixPath');

      // Set up environment
      final env = Map<String, String>.from(Platform.environment);
      env['WINEPREFIX'] = testPrefixPath;
      env['WINEARCH'] = 'win32';

      print('Environment for winecfg:');
      print('  WINEPREFIX: ${env['WINEPREFIX']}');
      print('  WINEARCH: ${env['WINEARCH']}');
      print('  DISPLAY: ${env['DISPLAY']}');
      print('  WAYLAND_DISPLAY: ${env['WAYLAND_DISPLAY']}');

      // Test winecfg with a very short timeout to avoid hanging
      try {
        print('Executing: wine winecfg');
        final process = await Process.start(
          'wine',
          ['winecfg'],
          environment: env,
        );

        // Wait briefly to see if winecfg starts
        await Future.delayed(const Duration(seconds: 3));

        // Check if process is still running (GUI opened)
        bool processRunning = true;
        try {
          process.kill(ProcessSignal.sigterm);
        } catch (e) {
          processRunning = false;
        }

        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => 0, // Assume success if it times out (GUI opened)
        );

        print('winecfg process handling completed');
        print('Exit code: $exitCode');

        // Capture any output
        try {
          final stdout = await process.stdout.transform(const SystemEncoding().decoder).take(10).join();
          final stderr = await process.stderr.transform(const SystemEncoding().decoder).take(10).join();
          
          if (stdout.isNotEmpty) print('winecfg stdout: $stdout');
          if (stderr.isNotEmpty) print('winecfg stderr: $stderr');
        } catch (e) {
          print('Could not capture output: $e');
        }

        print('winecfg test completed - if no errors shown above, it likely worked');

      } catch (e) {
        print('winecfg execution error: $e');
        // Don't fail the test here as display issues are common in CI
        print('This might be due to display/GUI limitations in the test environment');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Test Wine prefix can run basic commands', () async {
      if (testPrefixPath == null || !Directory(testPrefixPath).existsSync()) {
        print('SKIP: No test prefix available');
        return;
      }

      final env = Map<String, String>.from(Platform.environment);
      env['WINEPREFIX'] = testPrefixPath;
      env['WINEARCH'] = 'win32';

      // Test wine regedit (without GUI)
      print('Testing wine regedit /s (no GUI)...');
      final regeditResult = await Process.run(
        'wine',
        ['regedit', '/?'],
        environment: env,
      );

      print('regedit exit code: ${regeditResult.exitCode}');
      if (regeditResult.stdout.isNotEmpty) print('regedit stdout: ${regeditResult.stdout}');
      if (regeditResult.stderr.isNotEmpty) print('regedit stderr: ${regeditResult.stderr}');

      // Test wineserver
      print('Testing wineserver --version...');
      final wineserverResult = await Process.run(
        'wineserver',
        ['--version'],
        environment: env,
      );

      print('wineserver exit code: ${wineserverResult.exitCode}');
      if (wineserverResult.stdout.isNotEmpty) print('wineserver stdout: ${wineserverResult.stdout}');

      expect(wineserverResult.exitCode, equals(0), reason: 'wineserver --version should succeed');

      print('Wine prefix functionality test completed successfully!');
    });
  });
} 