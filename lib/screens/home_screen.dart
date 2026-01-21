import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/control_panel.dart';
import '../widgets/spectrum_view.dart';
import '../widgets/iq_view.dart';
import '../widgets/mqtt_log_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                      return appState.viewMode == ViewMode.spectrum
                          ? const SpectrumView()
                          : const IqView();
                    },
                  ),
                ),
              ],
            ),
          ),
          // Bottom MQTT log panel (always visible)
          const MqttLogPanel(),
        ],
      ),
    );
  }
}
