import 'package:flutter/material.dart';
import '../models/prefix_models.dart';
import '../models/settings.dart';
import 'prefix_creation_form.dart';

class PrefixCreationFormForType extends StatelessWidget {
  final Settings? settings;
  final PrefixType prefixType;

  const PrefixCreationFormForType({
    Key? key,
    required this.settings,
    required this.prefixType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Create the form with the specified prefix type
    return PrefixCreationForm(
      settings: settings,
      initialPrefixType: prefixType,
    );
  }
} 