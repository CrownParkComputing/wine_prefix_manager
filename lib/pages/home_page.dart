import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../models/prefix_models.dart'; // Import the prefix models
import '../providers/prefix_provider.dart'; // Import the PrefixProvider
import '../services/wine_component_installer.dart'; // Import the WineComponentInstaller
import 'prefix_management_page.dart'; // Import the PrefixManagementPage
import '../providers/window_control_provider.dart'; // Add this import

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  // Add window control provider instance
  final WindowControlProvider _windowControlProvider = WindowControlProvider();
  
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // ...existing code...
  }
  
  @override
  void dispose() {
    windowManager.removeListener(this);
    // ...existing code...
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Remove elevation to make it more seamless
        elevation: 0,
        // Add window drag area
        leading: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startDragging(),
          child: const Icon(Icons.wine_bar),
        ),
        title: GestureDetector(
          // Enable dragging from the title too
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startDragging(),
          child: const Text('Wine Prefix Manager'),
        ),
        actions: [
          // ...existing action icons...
          
          // Use local instance instead of Provider.of
          ..._windowControlProvider.getWindowButtons(),
        ],
      ),
      // ...existing code...
    );
  }
}