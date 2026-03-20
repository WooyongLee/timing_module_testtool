import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/transport_service.dart';
import '../services/transport_manager.dart';
import '../services/app_state.dart';
import '../constants/protocol.dart';

/// Placeholder widget for Spectrum view (will be replaced in Phase 2)
class SpectrumPlaceholder extends StatelessWidget {
  const SpectrumPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<TransportManager, AppState>(
      builder: (context, manager, appState, child) {
        final mqtt = manager.active;
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spectrum graph placeholder
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.show_chart,
                          size: 64,
                          color: Colors.green.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appState.spectrumData != null
                              ? 'Spectrum Data: ${Protocol.spectrumPoints} points'
                              : 'Spectrum Graph (8192 pts)',
                          style: TextStyle(
                            color: Colors.green.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                        if (appState.spectrumData != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Peak: ${appState.spectrumData!.findPeak().power.toStringAsFixed(1)} dBm @ ${appState.spectrumData!.findPeak().freqMhz.toStringAsFixed(3)} MHz',
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '(Graph will be implemented in Phase 2)',
                          style: TextStyle(
                            color: Colors.grey.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Controls
              _buildControls(context, mqtt, appState),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls(BuildContext context, TransportService mqtt, AppState appState) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Center frequency
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Center:'),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: TextField(
                controller: TextEditingController(
                  text: appState.centerFreqMhz.toStringAsFixed(3),
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                  suffixText: 'MHz',
                ),
                style: const TextStyle(fontSize: 14),
                keyboardType: TextInputType.number,
                onSubmitted: (value) {
                  final freq = double.tryParse(value);
                  if (freq != null) {
                    appState.centerFreqMhz = freq;
                  }
                },
              ),
            ),
          ],
        ),
        // RBW dropdown
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('RBW:'),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: appState.rbwIndex,
              items: Protocol.rbwOptions.map((rbw) {
                return DropdownMenuItem(
                  value: rbw.index,
                  child: Text(rbw.label),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  appState.rbwIndex = value;
                }
              },
            ),
          ],
        ),
        // MaxHold checkbox
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: appState.maxHold,
              onChanged: (value) {
                appState.maxHold = value ?? false;
              },
            ),
            const Text('MaxHold'),
          ],
        ),
        // Measurement buttons
        ElevatedButton(
          onPressed: mqtt.isInitialized && !appState.isMeasuring
              ? () => appState.startSingleMeasurement()
              : null,
          child: const Text('Single'),
        ),
        ElevatedButton(
          onPressed: mqtt.isInitialized
              ? () {
                  if (appState.isContinuous) {
                    appState.stopMeasurement();
                  } else {
                    appState.startContinuousMeasurement();
                  }
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: appState.isContinuous ? Colors.orange : null,
          ),
          child: Text(appState.isContinuous ? 'Stop' : 'Continuous'),
        ),
        // Status indicator
        if (appState.isMeasuring)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Measuring...'),
            ],
          ),
      ],
    );
  }
}
