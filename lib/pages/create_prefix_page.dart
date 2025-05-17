import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../widgets/prefix_creation_form.dart';
import '../providers/settings_provider.dart';
import '../models/prefix_models.dart'; // Add for PrefixType

class CreatePrefixPage extends StatefulWidget {
  const CreatePrefixPage({Key? key}) : super(key: key);

  @override
  State<CreatePrefixPage> createState() => _CreatePrefixPageState();
}

class _CreatePrefixPageState extends State<CreatePrefixPage> with TickerProviderStateMixin {
  // Add TabController for navigation between prefix types
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // Get settings from provider
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final settings = settingsProvider.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Prefix'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.sports_esports), text: 'Custom'),
            Tab(icon: Icon(Icons.wine_bar), text: 'Wine'),
            Tab(icon: Icon(Icons.games), text: 'Proton'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Custom Tab
          PrefixCreationForm(
            settings: settings,
            initialPrefixType: PrefixType.custom,
          ),
          
          // Wine Tab
          PrefixCreationForm(
            settings: settings,
            initialPrefixType: PrefixType.wine,
          ),
          
          // Proton Tab
          PrefixCreationForm(
            settings: settings,
            initialPrefixType: PrefixType.proton,
          ),
        ],
      ),
    );
  }
} 