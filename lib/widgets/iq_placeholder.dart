import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/app_state.dart';

/// Placeholder widget for IQ view (will be replaced in Phase 3)
class IqPlaceholder extends StatelessWidget {
  const IqPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MqttService, AppState>(
      builder: (context, mqtt, appState, child) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'IQ Capture',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  const Text('Bytes:'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: TextEditingController(
                        text: appState.iqByteSize.toString(),
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 14),
                      keyboardType: TextInputType.number,
                      onSubmitted: (value) {
                        final byteSize = int.tryParse(value);
                        if (byteSize != null) {
                          appState.iqByteSize = byteSize;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: mqtt.isInitialized && !appState.isMeasuring
                        ? () => appState.captureIq()
                        : null,
                    child: const Text('Capture'),
                  ),
                  if (appState.iqData != null) ...[
                    const SizedBox(width: 16),
                    Text(
                      'Captured: ${appState.iqData!.sampleCount} samples (${appState.iqByteSize} bytes)',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // IQ graph placeholders
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          appState.iqData != null
                              ? 'I Channel Data'
                              : 'I Channel',
                          style: TextStyle(
                            color: Colors.cyan.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          appState.iqData != null
                              ? 'Q Channel Data'
                              : 'Q Channel',
                          style: TextStyle(
                            color: Colors.orange.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '(IQ graphs will be implemented in Phase 3)',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
