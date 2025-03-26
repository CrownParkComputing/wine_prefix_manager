import 'package:flutter/material.dart';

class PrefixCreationPage extends StatefulWidget {
  const PrefixCreationPage({Key? key}) : super(key: key);

  @override
  State<PrefixCreationPage> createState() => _PrefixCreationPageState();
}

class _PrefixCreationPageState extends State<PrefixCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  String _selectedWineVersion = '';

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Prefix'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Prefix Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a prefix name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Prefix Path',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a prefix path';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  // Logic to create prefix would go here
                  Navigator.pop(context);
                }
              },
              child: const Text('Create Prefix'),
            ),
          ],
        ),
      ),
    );
  }
}
