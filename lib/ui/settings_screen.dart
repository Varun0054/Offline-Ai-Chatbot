import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _modelPathController = TextEditingController();
  final TextEditingController _threadsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _modelPathController.text = settings.modelPath;
    _threadsController.text = settings.cpuThreads.toString();
    // Trigger scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settings.scanForModels();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text(
                'Model Configuration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: settings.availableModels.contains(settings.modelPath) 
                          ? settings.modelPath 
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select Model',
                        border: OutlineInputBorder(),
                        helperText: 'Models in Download/Model folder',
                      ),
                      items: settings.availableModels.map((path) {
                        return DropdownMenuItem(
                          value: path,
                          child: Text(
                            path.split('/').last,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          settings.setModelPath(value);
                          _modelPathController.text = value;
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      await settings.scanForModels();
                    },
                    tooltip: 'Scan for models',
                  ),
                ],
              ),
              if (settings.availableModels.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'No models found. Click refresh to scan /Download/Model',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              // Manual override (optional, kept for flexibility)
              ExpansionTile(
                title: const Text("Advanced: Manual Path"),
                children: [
                   TextField(
                    controller: _modelPathController,
                    decoration: const InputDecoration(
                      labelText: 'Manual Model Path',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => settings.setModelPath(value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _threadsController,
                decoration: const InputDecoration(
                  labelText: 'CPU Threads',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final threads = int.tryParse(value);
                  if (threads != null) {
                    settings.setCpuThreads(threads);
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: settings.quantization,
                decoration: const InputDecoration(
                  labelText: 'Quantization Preset',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Q4_0', child: Text('Q4_0 (Fastest)')),
                  DropdownMenuItem(value: 'Q4_K_M', child: Text('Q4_K_M (Balanced)')),
                  DropdownMenuItem(value: 'Q5_K_M', child: Text('Q5_K_M (Better Quality)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    settings.setQuantization(value);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
