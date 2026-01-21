import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'spectrum_chart.dart';

class SpectrumView extends StatelessWidget {
  const SpectrumView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              // Title bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.show_chart, size: 20, color: Colors.teal),
                    const SizedBox(width: 8),
                    const Text(
                      'Spectrum View',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Marker info
                    if (appState.spectrumData != null && appState.markerEnabled)
                      _buildMarkerInfo(appState),
                  ],
                ),
              ),
              // Chart area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SpectrumChart(
                    spectrumData: appState.spectrumData,
                    maxHoldData: appState.maxHold ? appState.maxHoldData : null,
                    showPeakMarker: appState.markerEnabled,
                  ),
                ),
              ),
              // Bottom info bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Frequency range
                    if (appState.spectrumData != null)
                      Text(
                        '${appState.spectrumData!.startFreqMhz.toStringAsFixed(2)} ~ '
                        '${appState.spectrumData!.stopFreqMhz.toStringAsFixed(2)} MHz',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      )
                    else
                      const SizedBox(),
                    // Span info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Span : 61.44 MHz',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMarkerInfo(AppState appState) {
    final peak = appState.spectrumData!.findPeak();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, size: 14, color: Colors.red),
          const SizedBox(width: 4),
          Text(
            'Mrk1 : ${peak.power.toStringAsFixed(2)} dBm @ ${peak.freqMhz.toStringAsFixed(2)} MHz',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
