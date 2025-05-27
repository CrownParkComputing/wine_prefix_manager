import 'package:flutter/material.dart';
import '../models/prefix_models.dart';

class PrefixListTile extends StatelessWidget {
  final WinePrefix prefix;
  final VoidCallback? onTap; // Optional callback for tapping the tile itself

  const PrefixListTile({
    Key? key,
    required this.prefix,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        prefix.type == PrefixType.proton ? Icons.games : Icons.wine_bar,
        color: Theme.of(context).colorScheme.primary,
        size: 36, // Slightly larger icon
      ),
      title: Text(prefix.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        prefix.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: onTap, // Allow tapping the tile for potential future actions
      // Trailing actions (like delete, explore) will be inside the ExpansionTile content
    );
  }
}