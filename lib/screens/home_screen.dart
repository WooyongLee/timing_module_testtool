import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/control_panel.dart';
import '../widgets/spectrum_view.dart';
import '../widgets/iq_view.dart';
import '../widgets/tsync_view.dart';
import '../widgets/mqtt_log_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _logPanelHeight = 120.0; // Initial height
  final double _minLogPanelHeight = 60.0;
  final double _maxLogPanelHeight = 500.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('61.44MHz Test Tool'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        toolbarHeight: 40,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'About',
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: '61.44MHz Test Tool',
                applicationVersion: '1.0.0',
                children: [
                  const Text('AD9361 RF Transceiver Test Tool'),
                  const SizedBox(height: 8),
                  const Text('61.44MHz Clock Verification'),
                  const SizedBox(height: 8),
                  const Text('Protocol: 0x44/0x45'),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Main content area (left panel + chart view)
          Expanded(
            child: Row(
              children: [
                // Left control panel
                const ControlPanel(),
                // Right chart view (Spectrum or IQ based on viewMode)
                Expanded(
                  child: Consumer<AppState>(
                    builder: (context, appState, child) {
                      return switch (appState.viewMode) {
                        ViewMode.spectrum => const SpectrumView(),
                        ViewMode.iqData => const IqView(),
                        ViewMode.tsync => const TsyncView(),
                      };
                    },
                  ),
                ),
              ],
            ),
          ),
          // Resizable divider
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                setState(() {
                  _logPanelHeight = (_logPanelHeight - details.delta.dy)
                      .clamp(_minLogPanelHeight, _maxLogPanelHeight);
                });
              },
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  border: Border(
                    top: BorderSide(color: Colors.grey[700]!, width: 1),
                    bottom: BorderSide(color: Colors.grey[700]!, width: 1),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom MQTT log panel (resizable)
          MqttLogPanel(height: _logPanelHeight),
        ],
      ),
    );
  }
}
