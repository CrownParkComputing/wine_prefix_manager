import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/prefix_creation_form.dart';
import '../providers/settings_provider.dart';
import '../models/prefix_models.dart';

class CreatePrefixPage extends StatefulWidget {
  final VoidCallback? onSuccess;

  const CreatePrefixPage({super.key, this.onSuccess});

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

    // The main content is now returned directly, without Scaffold/AppBar
    return SingleChildScrollView( // Added SingleChildScrollView for dialog content
      child: Padding(
        padding: const EdgeInsets.all(24.0), // Increased padding for dialog look
        child: _selectedType == null
            // Step 1: Choose prefix type
            ? _buildPrefixTypeSelection()
            // Step 2: Show creation form based on selection
            : Column(
                mainAxisSize: MainAxisSize.min, // So column takes minimum space
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
                        'Create ${_selectedType == PrefixType.wine ? "Wine" : "Proton"} Prefix', // Updated title
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Show the appropriate creation form
                  // The PrefixCreationForm might need to be constrained in height
                  // or ensure it's also scrollable if it becomes too large.
                  Flexible( // Added Flexible to allow form to take available space
                    child: PrefixCreationForm(
                      settings: settings,
                      initialPrefixType: _selectedType!,
                      onSuccess: widget.onSuccess,
                      // Potentially add an onCancel or onCreated callback
                      // to close the dialog after creation/cancellation.
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPrefixTypeSelection() {
    // This part remains largely the same, but consider dialog context
    return Column( // Changed from Center to Column for better dialog layout
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 24), // Added some bottom padding
          TextButton(
            onPressed: () => Navigator.of(context).pop(), // Close button
            child: const Text('Cancel'),
          ),
        ],
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