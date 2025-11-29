import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
      body: Column(
        children: [
          // Custom Gradient Header
          Container(
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Settings',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Settings Content
          Expanded(
            child: Consumer<SettingsProvider>(
              builder: (context, settings, child) {
                return ListView(
                  padding: const EdgeInsets.all(20.0),
                  children: [
                    Text(
                      'Model Configuration',
                      style: GoogleFonts.poppins(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF4A00E0),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Model Selection
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: settings.availableModels.contains(settings.modelPath) 
                                    ? settings.modelPath 
                                    : null,
                                isExpanded: true,
                                hint: Text('Select Model', style: GoogleFonts.poppins()),
                                items: settings.availableModels.map((path) {
                                  return DropdownMenuItem(
                                    value: path,
                                    child: Text(
                                      path.split('/').last,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(),
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
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Color(0xFF4A00E0)),
                            onPressed: () async {
                              await settings.scanForModels();
                            },
                            tooltip: 'Scan for models',
                          ),
                        ],
                      ),
                    ),
                    if (settings.availableModels.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 8),
                        child: Text(
                          'No models found. Click refresh to scan /Download/Model',
                          style: GoogleFonts.poppins(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 24),
                    
                    // Advanced Manual Path
                    ExpansionTile(
                      title: Text(
                        "Advanced: Manual Path", 
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                      ),
                      children: [
                         Padding(
                           padding: const EdgeInsets.symmetric(vertical: 8.0),
                           child: TextField(
                            controller: _modelPathController,
                            decoration: InputDecoration(
                              labelText: 'Manual Model Path',
                              labelStyle: GoogleFonts.poppins(),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (value) => settings.setModelPath(value),
                                                   ),
                         ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // CPU Threads
                    TextField(
                      controller: _threadsController,
                      decoration: InputDecoration(
                        labelText: 'CPU Threads',
                        labelStyle: GoogleFonts.poppins(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final threads = int.tryParse(value);
                        if (threads != null) {
                          settings.setCpuThreads(threads);
                        }
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Quantization
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: settings.quantization,
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(value: 'Q4_0', child: Text('Q4_0 (Fastest)', style: GoogleFonts.poppins())),
                            DropdownMenuItem(value: 'Q4_K_M', child: Text('Q4_K_M (Balanced)', style: GoogleFonts.poppins())),
                            DropdownMenuItem(value: 'Q5_K_M', child: Text('Q5_K_M (Better Quality)', style: GoogleFonts.poppins())),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              settings.setQuantization(value);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
