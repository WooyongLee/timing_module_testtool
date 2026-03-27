import 'dart:async';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';
import '../services/tcp_server_service.dart';
import '../services/transport_service.dart';
import '../services/transport_manager.dart';
import '../services/app_state.dart';
import '../services/file_service.dart';
import '../constants/protocol.dart';
import '../models/device_status.dart';
import '../widgets/device_status_dialog.dart';
import '../screens/register_window.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  final _ipController   = TextEditingController(text: Protocol.defaultIp);
  final _portController = TextEditingController(text: '${Protocol.tcpServerPort}');

  List<String> _localIps = [];
  final _freqController = TextEditingController(text: '3000');
  final _captureLengthController = TextEditingController(text: '16384');
  final _fftLengthController = TextEditingController(text: '8192');
  final _repeatCountController = TextEditingController(text: '10');

  // T-Sync parameter controllers
  final _tsyncSamplesController   = TextEditingController(text: '2600000');
  final _tsyncHoTimeController    = TextEditingController(text: '30');
  final _tsyncDacController       = TextEditingController(text: '32768');
  final _tsyncRunNumberController = TextEditingController(text: '1');
  final _tsyncLoopCountController = TextEditingController(text: '0');
  final _tsyncDelayMsController   = TextEditingController(text: '500');

  // Track if controllers are initialized
  bool _controllersInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadLocalIps();
  }

  Future<void> _loadLocalIps() async {
    final ips = await TcpServerService.getLocalIpAddresses();
    if (mounted) setState(() => _localIps = ips);
  }

  // Status query subscription and timeout timer
  StreamSubscription? _statusSubscription;
  Timer? _statusTimeoutTimer;
  bool _isLoadingDialogOpen = false;

  // PLL Init state
  bool? _pllInitResult;   // null=not tried, true=success, false=failed
  bool _pllInitPending = false;
  StreamSubscription? _pllInitSubscription;


  void _sendPlInit(TransportService transport) {
    if (_pllInitPending) return;
    _pllInitSubscription?.cancel();
    setState(() {
      _pllInitPending = true;
      _pllInitResult = null;
    });
    transport.sendPlInit();
    _pllInitSubscription = transport.registerResponseStream
        .where((r) => r.subCommand == Protocol.typePlInit)
        .listen((r) {
          if (!mounted) return;
          final val = int.tryParse(r.params.isNotEmpty ? r.params[0] : '');
          setState(() {
            _pllInitResult = val == 1;
            _pllInitPending = false;
          });
          _pllInitSubscription?.cancel();
          _pllInitSubscription = null;
        });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _freqController.dispose();
    _captureLengthController.dispose();
    _fftLengthController.dispose();
    _repeatCountController.dispose();
    _tsyncSamplesController.dispose();
    _tsyncHoTimeController.dispose();
    _tsyncDacController.dispose();
    _tsyncRunNumberController.dispose();
    _tsyncLoopCountController.dispose();
    _tsyncDelayMsController.dispose();
    _statusSubscription?.cancel();
    _statusTimeoutTimer?.cancel();
    _pllInitSubscription?.cancel();
    super.dispose();
  }

  String _formatFreqMhz(double freq) {
    if (freq == freq.truncateToDouble()) return freq.toInt().toString();
    return freq.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
  }

  void _initControllersOnce(AppState appState) {
    if (!_controllersInitialized) {
      _freqController.text = _formatFreqMhz(appState.centerFreqMhz);
      _captureLengthController.text = appState.iqByteSize.toString();
      _fftLengthController.text = appState.fftLength.toString();
      _repeatCountController.text = appState.repeatCount.toString();
      _controllersInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<TransportManager, AppState>(
      builder: (context, manager, appState, child) {
        final mqtt = manager.active;
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
              // Transport Mode Toggle
              _buildSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Mode'),
                    _buildModeToggle(manager, mqtt),
                  ],
                ),
              ),
              const Divider(height: 1),

              // IP / Port Section
              _buildSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel(manager.mode == TransportMode.mqtt ? 'IP' : 'Port'),
                    manager.mode == TransportMode.mqtt
                        ? _buildIpInput(mqtt)
                        : _buildPortInput(mqtt),
                    if (manager.mode == TransportMode.tcpServer &&
                        _localIps.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildLocalIpHint(),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildConnectButton(manager, mqtt)),
                        const SizedBox(width: 4),
                        _buildRegisterButton(mqtt),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Single Request / Init AD9361 (hidden in tsync mode)
              if (appState.viewMode != ViewMode.tsync) ...[
                _buildSection(
                  child: _buildSingleRequestButton(mqtt, appState),
                ),
                const Divider(height: 1),

                // Status Query Button
                _buildSection(
                  child: _buildStatusQueryButton(mqtt),
                ),
                const Divider(height: 1),
              ],

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

              // Frequency Section (hidden in tsync mode)
              if (appState.viewMode != ViewMode.tsync) ...[
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Frequency'),
                      _buildFrequencyInput(appState),
                      const SizedBox(height: 6),
                      _buildLabel('RF Path'),
                      _buildRfPathDropdown(appState, mqtt),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],

              // RBW Section (hidden in tsync mode)
              if (appState.viewMode != ViewMode.tsync) ...[
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

                // Max Hold Section
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
              ],

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

              // tsync specific controls
              if (appState.viewMode == ViewMode.tsync) ...[
                // ── Init ─────────────────────────────────────────
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('ACQ Init'),
                      SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: mqtt.isConnected ? () => appState.tsyncInit() : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appState.tsyncInitialized ? Colors.green[600] : Colors.orange[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: Text(
                            appState.tsyncInitialized ? 'Initialized' : 'acqinit',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ── Param ────────────────────────────────────────
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('ACQ Param'),
                      _buildTsyncLabeledInput('Samples', _tsyncSamplesController, (v) {
                        final n = int.tryParse(v);
                        if (n != null) appState.tsyncSamples = n;
                      }),
                      const SizedBox(height: 4),
                      _buildTsyncLabeledInput('HO Time(s)', _tsyncHoTimeController, (v) {
                        final n = int.tryParse(v);
                        if (n != null) appState.tsyncHoTime = n;
                      }),
                      const SizedBox(height: 4),
                      _buildTsyncLabeledInput('DAC', _tsyncDacController, (v) {
                        final n = int.tryParse(v);
                        if (n != null) appState.tsyncDac = n;
                      }),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 26,
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: mqtt.isConnected ? () => appState.tsyncApplyParam() : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: const Text('Apply Param', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ── ACQ Run ──────────────────────────────────────
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('ACQ Run'),
                      _buildTsyncLabeledInput('Run Number', _tsyncRunNumberController, (v) {
                        final n = int.tryParse(v);
                        if (n != null && n > 0) appState.tsyncRunNumber = n;
                      }),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: mqtt.isConnected && !appState.tsyncRunning && !appState.tsyncLooping
                              ? () {
                                  final n = int.tryParse(_tsyncRunNumberController.text);
                                  if (n != null && n > 0) appState.tsyncRunNumber = n;
                                  appState.tsyncRun();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[600],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: appState.tsyncRunning
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Run', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ── ACQ Loop ─────────────────────────────────────
                _buildSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('ACQ Loop'),
                      _buildTsyncLabeledInput('Iterations', _tsyncLoopCountController, (v) {
                        final n = int.tryParse(v);
                        if (n != null && n >= 0) appState.tsyncLoopCount = n;
                      }),
                      const SizedBox(height: 4),
                      _buildTsyncLabeledInput('Delay(ms)', _tsyncDelayMsController, (v) {
                        final n = int.tryParse(v);
                        if (n != null && n >= 0) appState.tsyncDelayMs = n;
                      }),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: mqtt.isConnected && !appState.tsyncRunning
                              ? appState.tsyncLooping
                                  ? () => appState.tsyncStop()
                                  : () {
                                      final count = int.tryParse(_tsyncLoopCountController.text);
                                      if (count != null && count >= 0) appState.tsyncLoopCount = count;
                                      final delay = int.tryParse(_tsyncDelayMsController.text);
                                      if (delay != null && delay >= 0) appState.tsyncDelayMs = delay;
                                      appState.tsyncLoop();
                                    }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appState.tsyncLooping ? Colors.red[600] : Colors.green[600],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: Text(
                            appState.tsyncLooping ? 'Stop' : 'Loop',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ── Save CSV ─────────────────────────────────────
                _buildSection(
                  child: SizedBox(
                    height: 28,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: appState.tsyncResults.isNotEmpty
                          ? () async {
                              final path = await appState.tsyncExportCsv();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    path != null ? 'Saved: $path' : 'Export failed (no data or error)',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  duration: const Duration(seconds: 4),
                                  backgroundColor: path != null ? Colors.green[700] : Colors.red[700],
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.download, size: 14),
                      label: const Text('Save CSV', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
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

  Widget _buildIpInput(TransportService mqtt) {
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

  /// Shows local IPv4 addresses — the IP to write in tcp_server.conf.
  Widget _buildLocalIpHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.teal[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local IP (for tcp_server.conf):',
            style: TextStyle(fontSize: 9, color: Colors.teal[700]),
          ),
          ..._localIps.map((ip) => GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: ip));
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ip,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.teal[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(Icons.copy, size: 11, color: Colors.teal[400]),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPortInput(TransportService mqtt) {
    return SizedBox(
      height: 28,
      child: TextField(
        controller: _portController,
        enabled: !mqtt.isConnected,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          filled: true,
          fillColor: Colors.white,
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildModeToggle(TransportManager manager, TransportService mqtt) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TransportMode>(
          value: manager.mode,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: const [
            DropdownMenuItem(
              value: TransportMode.mqtt,
              child: Text('MQTT', style: TextStyle(fontSize: 12)),
            ),
            DropdownMenuItem(
              value: TransportMode.tcpServer,
              child: Text('TCP Server', style: TextStyle(fontSize: 12)),
            ),
          ],
          onChanged: mqtt.isConnected
              ? null
              : (value) {
                  if (value != null) manager.switchMode(value);
                },
        ),
      ),
    );
  }

  Widget _buildConnectButton(TransportManager manager, TransportService mqtt) {
    final isTcpMode = manager.mode == TransportMode.tcpServer;
    final isListening = isTcpMode &&
        mqtt.connectionState == ConnectionState.connecting;

    String label;
    if (mqtt.isConnected) {
      label = 'Stop';
    } else if (isListening) {
      label = 'Listening...';
    } else {
      label = isTcpMode ? 'Listen' : 'Connect';
    }

    return SizedBox(
      height: 28,
      child: ElevatedButton(
        onPressed: isListening && !mqtt.isConnected
            ? () => mqtt.disconnect()
            : mqtt.connectionState == ConnectionState.connecting && !isTcpMode
                ? null
                : () {
                    if (mqtt.isConnected || isListening) {
                      mqtt.disconnect();
                    } else {
                      final address = isTcpMode
                          ? _portController.text
                          : _ipController.text;
                      mqtt.connect(address);
                    }
                  },
        style: ElevatedButton.styleFrom(
          backgroundColor: mqtt.isConnected
              ? Colors.red[400]
              : isListening
                  ? Colors.orange[400]
                  : Colors.blue[400],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildRegisterButton(TransportService mqtt) {
    return SizedBox(
      height: 28,
      width: 28,
      child: IconButton(
        onPressed: mqtt.isConnected
            ? () => showRegisterWindow(context, mqtt)
            : null,
        icon: const Icon(Icons.memory, size: 16),
        padding: EdgeInsets.zero,
        tooltip: 'Registers',
        style: IconButton.styleFrom(
          backgroundColor: mqtt.isConnected ? Colors.teal[50] : null,
          foregroundColor: mqtt.isConnected ? Colors.teal : Colors.grey,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          side: BorderSide(color: mqtt.isConnected ? Colors.teal : Colors.grey[400]!),
        ),
      ),
    );
  }

  Widget _buildSingleRequestButton(TransportService mqtt, AppState appState) {
    final isEnabled = mqtt.isConnected && !appState.isMeasuring;
    final isSpectrum = appState.viewMode == ViewMode.spectrum;
    final buttonText = isSpectrum ? 'Single FFT' : 'IQ Capture';
    final buttonIcon = isSpectrum ? Icons.show_chart : Icons.waves;

    return Column(
      children: [
        // PLL Init button
        SizedBox(
          height: 32,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: mqtt.isConnected && !_pllInitPending
                ? () => _sendPlInit(mqtt)
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: _pllInitResult == null
                  ? Colors.blueGrey[700]
                  : _pllInitResult!
                      ? Colors.green[700]
                      : Colors.red[700],
              side: BorderSide(
                color: _pllInitResult == null
                    ? Colors.blueGrey[400]!
                    : _pllInitResult!
                        ? Colors.green[600]!
                        : Colors.red[600]!,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_pllInitPending)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blueGrey[400]),
                  )
                else
                  Icon(
                    _pllInitResult == null
                        ? Icons.settings_input_antenna
                        : _pllInitResult!
                            ? Icons.check_circle
                            : Icons.cancel,
                    size: 14,
                  ),
                const SizedBox(width: 4),
                Text(
                  _pllInitPending
                      ? 'PLL Init...'
                      : _pllInitResult == null
                          ? 'PLL Init'
                          : _pllInitResult!
                              ? 'PLL Locked'
                              : 'PLL Failed',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // AD9361 Init button
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
            DropdownMenuItem(
              value: ViewMode.tsync,
              child: Text('tsync', style: TextStyle(fontSize: 12)),
            ),
          ],
          onChanged: appState.isMeasuring ? null : (value) {
            if (value != null) {
              appState.viewMode = value;
            }
          },
        ),
      ),
    );
  }

  Widget _buildTsyncLabeledInput(
    String label,
    TextEditingController ctrl,
    void Function(String) onSubmit,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ),
        Expanded(
          child: SizedBox(
            height: 24,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              onSubmitted: onSubmit,
              onEditingComplete: () => onSubmit(ctrl.text),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencyInput(AppState appState) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 28,
            child: Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) {
                  _applyFrequency(appState);
                }
              },
              child: TextField(
                controller: _freqController,
                enabled: !appState.isMeasuring,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                style: const TextStyle(fontSize: 12),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onSubmitted: (value) => _applyFrequency(appState),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Text('MHz', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildRfPathDropdown(AppState appState, TransportService transport) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[400]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: appState.rfPath,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Path 0')),
            DropdownMenuItem(value: 1, child: Text('Path 1')),
          ],
          onChanged: transport.isConnected
              ? (val) {
                  if (val == null) return;
                  appState.setRfPath(val);
                }
              : null,
        ),
      ),
    );
  }

  void _applyFrequency(AppState appState) {
    final freq = double.tryParse(_freqController.text);
    if (freq != null && freq >= 60 && freq <= 6000) {
      appState.centerFreqMhz = freq;
      _freqController.text = _formatFreqMhz(freq);
    } else {
      _freqController.text = _formatFreqMhz(appState.centerFreqMhz);
    }
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
                onChanged: appState.isMeasuring ? null : (value) {
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
          onChanged: appState.isMeasuring ? null : (value) {
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
          onChanged: appState.isMeasuring ? null : (value) {
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
          enabled: !appState.isMeasuring,
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
          enabled: !appState.isMeasuring,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            filled: true,
            fillColor: Colors.white,
            hintText: 'max 1000',
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
    if (count != null && count > 0 && count <= 1000) {
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
          enabled: !appState.isMeasuring,
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
                onChanged: appState.isMeasuring ? null : (value) {
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

  Widget _buildStatusQueryButton(TransportService mqtt) {
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

  void _requestDeviceStatus(TransportService mqtt) {
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

  Widget _buildConnectionStatus(TransportService mqtt) {
    Color statusColor;
    String statusText;
    String? subText;

    final isTcp = mqtt is TcpServerService;

    switch (mqtt.connectionState) {
      case ConnectionState.connected:
        statusColor = Colors.green;
        statusText = 'Connected';
        if (isTcp && mqtt.brokerIp.isNotEmpty) {
          subText = mqtt.brokerIp;
        }
        break;
      case ConnectionState.connecting:
        statusColor = Colors.orange;
        statusText = isTcp ? 'Listening :${(mqtt as TcpServerService).listenPort}' : 'Connecting...';
        break;
      case ConnectionState.error:
        statusColor = Colors.red;
        statusText = 'Error';
        if (mqtt.lastError.isNotEmpty) {
          subText = mqtt.lastError.length > 28
              ? '${mqtt.lastError.substring(0, 28)}…'
              : mqtt.lastError;
        }
        break;
      case ConnectionState.disconnected:
        statusColor = Colors.grey;
        statusText = 'Disconnected';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subText != null)
                  Text(
                    subText,
                    style: TextStyle(fontSize: 10, color: statusColor.withOpacity(0.8)),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
