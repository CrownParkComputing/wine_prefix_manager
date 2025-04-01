import 'package:flutter/material.dart';
import 'package:wine_prefix_manager/models/game.dart';  // Adjust based on your actual model path

class GameDetailsView extends StatefulWidget {
  final Game game;  // Assuming you have a Game model
  
  const GameDetailsView({Key? key, required this.game}) : super(key: key);

  @override
  _GameDetailsViewState createState() => _GameDetailsViewState();
}

class _GameDetailsViewState extends State<GameDetailsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.game.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.info), text: 'Details'),
            Tab(icon: Icon(Icons.settings), text: 'Configuration'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Performance'),
            Tab(icon: Icon(Icons.history), text: 'Play History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Details Tab
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Game cover/banner image
                if (widget.game.coverUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.game.coverUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 16),
                // Game description and basic details
                Text(
                  widget.game.description ?? 'No description available',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Wine Version', widget.game.wineVersion ?? 'Not specified'),
                _buildInfoRow('Prefix Path', widget.game.prefixPath ?? 'Not specified'),
                _buildInfoRow('Install Date', widget.game.installDate?.toString() ?? 'Unknown'),
              ],
            ),
          ),
          
          // Configuration Tab
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Wine Configuration', 
                          style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        _buildConfigOption('Windows Version', 'Windows 10'),
                        _buildConfigOption('DXVK', 'Enabled'),
                        _buildConfigOption('Virtual Desktop', 'Disabled'),
                        // More config options
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    // Open wine configuration dialog/screen
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Edit Wine Configuration'),
                ),
              ],
            ),
          ),
          
          // Performance Tab
          Center(
            child: Text('Performance data and graphs would appear here'),
          ),
          
          // Play History Tab
          ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: 5, // Example count, would actually use game.playHistory?.length ?? 0
            itemBuilder: (context, index) {
              // Would actually use game.playHistory[index]
              return ListTile(
                leading: const Icon(Icons.access_time),
                title: Text('Play Session ${index + 1}'),
                subtitle: Text('Duration: ${(index + 1) * 30} minutes'),
                trailing: Text('2023-0${index + 1}-01'),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
  
  Widget _buildConfigOption(String name, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
