import 'dart:async';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/app_state.dart';
import '../services/file_service.dart';
import '../constants/protocol.dart';
import '../models/device_status.dart';
import '../widgets/device_status_dialog.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  final _ipController = TextEditingController(text: Protocol.defaultIp);
  final _freqController = TextEditingController(text: '3000');
  final _captureLengthController = TextEditingController(text: '16384');
  final _fftLengthController = TextEditingController(text: '8192');
  final _repeatCountController = TextEditingController(text: '10');

  // Track if controllers are initialized
  bool _controllersInitialized = false;

  // Status query subscription and timeout timer
  StreamSubscription? _statusSubscription;
  Timer? _statusTimeoutTimer;
  bool _isLoadingDialogOpen = false;

  @override
  void dispose() {
    _ipController.dispose();
    _freqController.dispose();
    _captureLengthController.dispose();
    _fftLengthController.dispose();
    _repeatCountController.dispose();
    _statusSubscription?.cancel();
    _statusTimeoutTimer?.cancel();
    super.dispose();
  }

  void _initControllersOnce(AppState appState) {
    if (!_controllersInitialized) {
      _freqController.text = appState.centerFreqMhz.toString();
      _captureLengthController.text = appState.iqByteSize.toString();
      _fftLengthController.text = appState.fftLength.toString();
      _repeatCountController.text = appState.repeatCount.toString();
      _controllersInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MqttService, AppState>(
      builder: (context, mqtt, appState, child) {
        // Initialize controllers only once
        _initControllersOnce(appState);

        return Container(
          width: 180,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(right: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // IP Section
              _buildSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('IP'),
                    _buildIpInput(mqtt),
                    const SizedBox(height: 8),
                    _buildConnectButton(mqtt),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Single Request Button (FFT or IQ Capture)
              _buildSection(
                child: _buildSingleRequestButton(mqtt, appState),
              ),
              const Divider(height: 1),

              // Status Query Button
              _buildSection(
                child: _buildStatusQueryButton(mqtt),
              ),
              const Divider(height: 1),

              // Meas. Type Section
              _buildSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Meas. Type'),
                    _buildMeasTypeDropdown(appState),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Frequency Section
              _buildSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Frequency'),
                    _buildFrequencyInput(appState),
                  ],
                ),
              ),
              const Divider(height: 1),

              // RBW Section
              _buildSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('RBW'),
                    _buildRbwDropdown(appState),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Max Hold Section (Spectrum only)
              _buildSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Max Hold'),
                    _buildMaxHoldDropdown(appState),
                    const SizedBox(height: 6),
                    _buildMaxHoldClearButton(appState),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Spectrum specific controls
              if (appState.viewMode == ViewMode.spectrum) ...[
                // FFT Length Section
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('FFT Length'),
                      _buildFftLengthInput(appState),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Repeat Count Section
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Repeat Count'),
                      _buildRepeatCountInput(appState),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Chart Update Interval Section
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Update Interval'),
                      _buildUpdateIntervalDropdown(appState),
                      const SizedBox(height: 4),
                      _buildQueueStatusText(appState),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Marker Section
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Marker'),
                      _buildMarkerDropdown(appState),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Save FFT Section
                _buildSection(
                  child: _buildSaveFftButton(appState),
                ),
                const Divider(height: 1),
              ],

              // IQ Data specific controls
              if (appState.viewMode == ViewMode.iqData) ...[
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Capture Bytes'),
                      _buildCaptureLengthInput(appState),
                      const SizedBox(height: 4),
                      Text(
                        '= ${appState.iqByteSize ~/ 8} samples',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _buildSection(
                  child: _buildSaveButton(appState),
                ),
                const Divider(height: 1),
              ],

              // Spacer
              const Expanded(child: SizedBox()),

              // Connection status at bottom
              _buildConnectionStatus(mqtt),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: child,
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildIpInput(MqttService mqtt) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: _ipController,
              enabled: !mqtt.isConnected,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectButton(MqttService mqtt) {
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        onPressed: mqtt.connectionState == ConnectionState.connecting
            ? null
            : () {
                if (mqtt.isConnected) {
                  mqtt.disconnect();
                } else {
                  mqtt.connect(_ipController.text);
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: mqtt.isConnected ? Colors.red[400] : Colors.blue[400],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(
          mqtt.isConnected ? 'Disconnect' : 'Connect',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildSingleRequestButton(MqttService mqtt, AppState appState) {
    final isEnabled = mqtt.isConnected && !appState.isMeasuring;
    final isSpectrum = appState.viewMode == ViewMode.spectrum;
    final buttonText = isSpectrum ? 'Single FFT' : 'IQ Capture';
    final buttonIcon = isSpectrum ? Icons.show_chart : Icons.waves;

    return Column(
      children: [
        // Init button
        SizedBox(
          height: 32,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: mqtt.isConnected && !mqtt.isInitialized
                ? () => appState.initialize()
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: mqtt.isInitialized ? Colors.green : Colors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  mqtt.isInitialized ? Icons.check_circle : Icons.play_circle_outline,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  mqtt.isInitialized ? 'Initialized' : 'Init AD9361',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Single request button
        SizedBox(
          height: 36,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isEnabled && mqtt.isInitialized
                ? () {
                    if (isSpectrum) {
                      appState.requestSpectrum();
                    } else {
                      appState.requestIqCapture();
                    }
                  }
                : null,
            icon: Icon(buttonIcon, size: 16),
            label: Text(buttonText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isSpectrum ? Colors.blue[600] : Colors.purple[600],
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[400],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),
        // Repeated FFT button (spectrum only)
        if (isSpectrum) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isEnabled && mqtt.isInitialized
                  ? () => appState.requestRepeatedSpectrum()
                  : null,
              icon: const Icon(Icons.repeat, size: 16),
              label: const Text('Repeat FFT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[400],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ],
        if (appState.isMeasuring)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue[600],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Measuring...',
                      style: TextStyle(fontSize: 11, color: Colors.blue[600]),
                    ),
                  ],
                ),
                if (appState.totalCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${appState.currentIteration} / ${appState.totalCount}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMeasTypeDropdown(AppState appState) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ViewMode>(
          value: appState.viewMode,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: const [
            DropdownMenuItem(
              value: ViewMode.spectrum,
              child: Text('Spectrum', style: TextStyle(fontSize: 12)),
            ),
            DropdownMenuItem(
              value: ViewMode.iqData,
              child: Text('IQ Data', style: TextStyle(fontSize: 12)),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              appState.viewMode = value;
            }
          },
        ),
      ),
    );
  }

  Widget _buildFrequencyInput(AppState appState) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: _freqController,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 12),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (value) {
                final freq = int.tryParse(value);
                if (freq != null) {
                  appState.centerFreqMhz = freq;
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Text('MHz', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildRbwDropdown(AppState appState) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: appState.rbwIndex,
                isExpanded: true,
                isDense: true,
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                items: Protocol.rbwOptions.map((rbw) {
                  return DropdownMenuItem(
                    value: rbw.index,
                    child: Text(
                      rbw.valueHz >= 1000 ? '${rbw.valueHz ~/ 1000}' : '${rbw.valueHz}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    appState.rbwIndex = value;
                  }
                },
              ),
            ),
          ),
          const Text('kHz', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMaxHoldDropdown(AppState appState) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<bool>(
          value: appState.maxHold,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: const [
            DropdownMenuItem(
              value: false,
              child: Text('Off', style: TextStyle(fontSize: 12)),
            ),
            DropdownMenuItem(
              value: true,
              child: Text('On', style: TextStyle(fontSize: 12)),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              appState.maxHold = value;
            }
          },
        ),
      ),
    );
  }

  Widget _buildMaxHoldClearButton(AppState appState) {
    return SizedBox(
      height: 24,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: appState.maxHold && appState.maxHoldData != null
            ? () => appState.clearMaxHold()
            : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: const Text(
          'Clear',
          style: TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildMarkerDropdown(AppState appState) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<bool>(
          value: appState.markerEnabled,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: const [
            DropdownMenuItem(
              value: false,
              child: Text('Off', style: TextStyle(fontSize: 12)),
            ),
            DropdownMenuItem(
              value: true,
              child: Text('On', style: TextStyle(fontSize: 12)),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              appState.markerEnabled = value;
            }
          },
        ),
      ),
    );
  }

  Widget _buildFftLengthInput(AppState appState) {
    return SizedBox(
      height: 28,
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) {
            _applyFftLength(appState);
          }
        },
        child: TextField(
          controller: _fftLengthController,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            filled: true,
            fillColor: Colors.white,
            hintText: 'max ${Protocol.maxFftLength}',
            hintStyle: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          style: const TextStyle(fontSize: 12),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (value) => _applyFftLength(appState),
        ),
      ),
    );
  }

  void _applyFftLength(AppState appState) {
    final len = int.tryParse(_fftLengthController.text);
    if (len != null && len > 0 && len <= Protocol.maxFftLength) {
      appState.fftLength = len;
    } else {
      _fftLengthController.text = appState.fftLength.toString();
    }
  }

  Widget _buildRepeatCountInput(AppState appState) {
    return SizedBox(
      height: 28,
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) {
            _applyRepeatCount(appState);
          }
        },
        child: TextField(
          controller: _repeatCountController,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            filled: true,
            fillColor: Colors.white,
            hintText: 'max 10000',
            hintStyle: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          style: const TextStyle(fontSize: 12),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (value) => _applyRepeatCount(appState),
        ),
      ),
    );
  }

  void _applyRepeatCount(AppState appState) {
    final count = int.tryParse(_repeatCountController.text);
    if (count != null && count > 0 && count <= 10000) {
      appState.repeatCount = count;
    } else {
      _repeatCountController.text = appState.repeatCount.toString();
    }
  }

  Widget _buildCaptureLengthInput(AppState appState) {
    return SizedBox(
      height: 28,
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) {
            _applyCaptureLength(appState);
          }
        },
        child: TextField(
          controller: _captureLengthController,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            filled: true,
            fillColor: Colors.white,
            hintText: 'max ${Protocol.maxIqSamples * 4}',
            hintStyle: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          style: const TextStyle(fontSize: 12),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (value) => _applyCaptureLength(appState),
        ),
      ),
    );
  }

  void _applyCaptureLength(AppState appState) {
    final byteSize = int.tryParse(_captureLengthController.text);
    if (byteSize != null && byteSize >= 4 && byteSize <= Protocol.maxIqSamples * 4) {
      appState.iqByteSize = byteSize;
    } else {
      _captureLengthController.text = appState.iqByteSize.toString();
    }
  }

  Widget _buildSaveFftButton(AppState appState) {
    return SizedBox(
      height: 32,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: appState.spectrumData != null
            ? () => _saveFftData(context, appState)
            : null,
        icon: const Icon(Icons.save, size: 16),
        label: const Text('Save FFT', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[600],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  Future<void> _saveFftData(BuildContext context, AppState appState) async {
    if (appState.spectrumData == null) return;

    final path = await FileService.saveFftToAutoPath(appState.spectrumData!);
    if (context.mounted) {
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('FFT saved to: $path'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save FFT data'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildSaveButton(AppState appState) {
    return SizedBox(
      height: 32,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: appState.iqData != null
            ? () => _saveIqData(context, appState)
            : null,
        icon: const Icon(Icons.save, size: 16),
        label: const Text('Save', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  Future<void> _saveIqData(BuildContext context, AppState appState) async {
    if (appState.iqData == null) return;

    final path = await FileService.saveIqCsv(appState.iqData!);
    if (context.mounted) {
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to: $path'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Widget _buildUpdateIntervalDropdown(AppState appState) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: appState.chartUpdateIntervalMs,
                isExpanded: true,
                isDense: true,
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                items: const [
                  DropdownMenuItem(
                    value: 100,
                    child: Text('100', style: TextStyle(fontSize: 12)),
                  ),
                  DropdownMenuItem(
                    value: 200,
                    child: Text('200', style: TextStyle(fontSize: 12)),
                  ),
                  DropdownMenuItem(
                    value: 300,
                    child: Text('300', style: TextStyle(fontSize: 12)),
                  ),
                  DropdownMenuItem(
                    value: 500,
                    child: Text('500', style: TextStyle(fontSize: 12)),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    appState.chartUpdateIntervalMs = value;
                  }
                },
              ),
            ),
          ),
          const Text('ms', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildQueueStatusText(AppState appState) {
    if (appState.queuedSpectrumCount == 0) {
      return const SizedBox.shrink();
    }

    return Text(
      'Queue: ${appState.queuedSpectrumCount}',
      style: TextStyle(
        fontSize: 10,
        color: appState.queuedSpectrumCount > 10 ? Colors.orange : Colors.grey[600],
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _buildStatusQueryButton(MqttService mqtt) {
    final isEnabled = mqtt.isConnected && mqtt.isInitialized;

    return SizedBox(
      height: 32,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isEnabled
            ? () => _requestDeviceStatus(mqtt)
            : null,
        icon: const Icon(Icons.info_outline, size: 16),
        label: const Text('Device Status', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.teal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  void _requestDeviceStatus(MqttService mqtt) {
    // Cancel any existing timer and subscription
    _statusTimeoutTimer?.cancel();
    _statusSubscription?.cancel();

    // Subscribe to status stream
    _statusSubscription = mqtt.statusStream.listen((statusResponse) {
      _handleStatusResponse(statusResponse);
    });

    // Send status query command
    mqtt.sendStatusQueryCommand();

    // Show loading indicator
    _isLoadingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Requesting device status...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Auto-close loading dialog after timeout (only if still loading)
    _statusTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoadingDialogOpen) {
        _isLoadingDialogOpen = false;
        Navigator.of(context).pop();

        // Show timeout error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status request timed out'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _handleStatusResponse(String response) {
    // Cancel timeout timer
    _statusTimeoutTimer?.cancel();

    // Close loading dialog if open
    if (mounted && _isLoadingDialogOpen) {
      _isLoadingDialogOpen = false;
      Navigator.of(context).pop();
    }

    try {
      final status = DeviceStatus.fromMqttResponse(response);

      // Show status dialog (this should stay open until user closes it)
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true, // Allow closing by clicking outside
          builder: (context) => DeviceStatusDialog(status: status),
        );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to parse status: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildConnectionStatus(MqttService mqtt) {
    Color statusColor;
    String statusText;

    switch (mqtt.connectionState) {
      case ConnectionState.connected:
        statusColor = Colors.green;
        statusText = 'Connected';
        break;
      case ConnectionState.connecting:
        statusColor = Colors.orange;
        statusText = 'Connecting...';
        break;
      case ConnectionState.error:
        statusColor = Colors.red;
        statusText = 'Error';
        break;
      case ConnectionState.disconnected:
        statusColor = Colors.grey;
        statusText = 'Disconnected';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
