import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../widgets/prefix_creation_form.dart';
import '../providers/settings_provider.dart';
import '../models/prefix_models.dart';

class CreatePrefixPage extends StatefulWidget {
  const CreatePrefixPage({Key? key}) : super(key: key);

  @override
  State<CreatePrefixPage> createState() => _CreatePrefixPageState();
}

class _CreatePrefixPageState extends State<CreatePrefixPage> {
  PrefixType? _selectedType;

  @override
  Widget build(BuildContext context) {
    // Get settings from provider
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final settings = settingsProvider.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Prefix'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _selectedType == null
            // Step 1: Choose prefix type
            ? _buildPrefixTypeSelection()
            // Step 2: Show creation form based on selection
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with back button
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          setState(() {
                            _selectedType = null;
                          });
                        },
                      ),
                      Text(
                        '${_selectedType == PrefixType.wine ? "Wine" : "Proton"} Prefix',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Show the appropriate creation form
                  Expanded(
                    child: PrefixCreationForm(
                      settings: settings,
                      initialPrefixType: _selectedType!,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPrefixTypeSelection() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Select Prefix Type',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Wine Option
              Expanded(
                child: _buildPrefixTypeCard(
                  icon: Icons.wine_bar,
                  title: 'Wine',
                  description: 'Standard Wine prefix for running Windows applications',
                  prefixType: PrefixType.wine,
                ),
              ),
              const SizedBox(width: 16),
              // Proton Option
              Expanded(
                child: _buildPrefixTypeCard(
                  icon: Icons.games,
                  title: 'Proton',
                  description: 'Steam Proton prefix optimized for gaming',
                  prefixType: PrefixType.proton,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrefixTypeCard({
    required IconData icon,
    required String title,
    required String description,
    required PrefixType prefixType,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedType = prefixType;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 