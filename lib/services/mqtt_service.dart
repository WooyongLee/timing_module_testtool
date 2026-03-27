import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart' hide Protocol;
import 'package:mqtt_client/mqtt_server_client.dart';
import '../constants/protocol.dart';
import '../models/tsync_data.dart';
import 'transport_service.dart';

// Re-export shared types so existing `import 'mqtt_service.dart'` still works.
export 'transport_service.dart'
    show
        ConnectionState,
        MqttLogEntry,
        MqttResponse,
        TsyncAck,
        RegisterResponse,
        TransportService;

/// MQTT Service for communication with Combo FW
class MqttService extends TransportService {
  MqttServerClient? _client;
  ConnectionState _connectionState = ConnectionState.disconnected;
  String _lastError = '';
  String _brokerIp = Protocol.defaultIp;
  bool _isInitialized = false;

  // Stream controllers for data
  final _responseController = StreamController<MqttResponse>.broadcast();
  final _spectrumDataController = StreamController<Uint8List>.broadcast();
  final _iqDataController = StreamController<Uint8List>.broadcast();
  final _logController = StreamController<MqttLogEntry>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _registerResponseController = StreamController<RegisterResponse>.broadcast();

  // T-Sync ACQ stream controllers
  final _tsyncIterController      = StreamController<TsyncIterResult>.broadcast();
  final _tsyncStatusController    = StreamController<TsyncStatus>.broadcast();
  final _tsyncAcqResultController = StreamController<TsyncAcqResult>.broadcast();
  final _tsyncAckController       = StreamController<TsyncAck>.broadcast();

  int _pendingDataSize = 0;

  // Pending binary data info
  int _pendingDataType = -1;

  // Log history
  final List<MqttLogEntry> _logHistory = [];
  static const int maxLogEntries = 500;

  // Getters
  ConnectionState get connectionState => _connectionState;
  String get lastError => _lastError;
  String get brokerIp => _brokerIp;
  bool get isConnected => _connectionState == ConnectionState.connected;
  bool get isInitialized => _isInitialized;
  List<MqttLogEntry> get logHistory => List.unmodifiable(_logHistory);

  Stream<MqttResponse> get responseStream => _responseController.stream;
  Stream<Uint8List> get spectrumDataStream => _spectrumDataController.stream;
  Stream<Uint8List> get iqDataStream => _iqDataController.stream;
  Stream<MqttLogEntry> get logStream => _logController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<RegisterResponse> get registerResponseStream => _registerResponseController.stream;

  // T-Sync ACQ streams
  Stream<TsyncIterResult> get tsyncIterStream      => _tsyncIterController.stream;
  Stream<TsyncStatus>     get tsyncStatusStream    => _tsyncStatusController.stream;
  Stream<TsyncAcqResult>  get tsyncAcqResultStream => _tsyncAcqResultController.stream;
  Stream<TsyncAck>        get tsyncAckStream       => _tsyncAckController.stream;

  void _addLog(MqttLogEntry entry) {
    _logHistory.add(entry);
    if (_logHistory.length > maxLogEntries) {
      _logHistory.removeAt(0);
    }
    _logController.add(entry);
    notifyListeners();
  }

  void clearLogs() {
    _logHistory.clear();
    notifyListeners();
  }

  /// Connect to MQTT broker
  Future<bool> connect(String brokerIp) async {
    if (_connectionState == ConnectionState.connecting) {
      return false;
    }

    _brokerIp = brokerIp;
    _connectionState = ConnectionState.connecting;
    _lastError = '';
    notifyListeners();

    try {
      _client = MqttServerClient(brokerIp, 'flutter_test_app_${DateTime.now().millisecondsSinceEpoch}');
      _client!.port = Protocol.mqttPort;
      _client!.keepAlivePeriod = 60;
      _client!.logging(on: false);
      _client!.autoReconnect = true;
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onAutoReconnect = _onAutoReconnect;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier('flutter_test_app')
          .startClean()
          .withWillQos(MqttQos.atMostOnce);

      _client!.connectionMessage = connMessage;

      await _client!.connect();

      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        // Subscribe to data topics
        _client!.subscribe(Protocol.dataTopic, MqttQos.atMostOnce);
        _client!.subscribe(Protocol.data2Topic, MqttQos.atMostOnce);
        _client!.updates?.listen(_onMessage);

        _connectionState = ConnectionState.connected;
        _addLog(MqttLogEntry(
          direction: 'SYS',
          topic: '',
          message: 'Connected to $brokerIp',
        ));
        notifyListeners();
        return true;
      } else {
        _connectionState = ConnectionState.error;
        _lastError = 'Connection failed: ${_client!.connectionStatus?.state}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _connectionState = ConnectionState.error;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from MQTT broker
  void disconnect() {
    _client?.disconnect();
    _connectionState = ConnectionState.disconnected;
    _isInitialized = false;
    _addLog(MqttLogEntry(
      direction: 'SYS',
      topic: '',
      message: 'Disconnected',
    ));
    notifyListeners();
  }

  /// Send command to FW
  void sendCommand(String command) {
    if (!isConnected || _client == null) {
      debugPrint('MQTT: Not connected, cannot send command');
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    _client!.publishMessage(
      Protocol.commandTopic,
      MqttQos.atMostOnce,
      builder.payload!,
    );
    debugPrint('MQTT TX: $command');
    _addLog(MqttLogEntry(
      direction: 'TX',
      topic: Protocol.commandTopic,
      message: command,
    ));
  }

  /// Initialize AD9361 61.44MHz mode
  void sendInitCommand() {
    sendCommand('0x44 0x00');
  }

  /// Request FFT spectrum measurement (single shot)
  /// Protocol: 0x44 0x01 <freq_hz> <rbw_hz> <fft_size>
  @override
  void sendSpectrumCommand({
    required int freqHz,
    required int rbwHz,
    int fftLen = Protocol.defaultFftLength,
  }) {
    sendCommand('0x44 0x01 $freqHz $rbwHz $fftLen');
    _pendingDataType = Protocol.typeSpectrum;
    _pendingDataSize = fftLen * 4;
  }

  /// Request repeated FFT spectrum measurement
  /// Protocol: 0x44 0x04 <freq_hz> <rbw_hz> <fft_size> <count>
  void sendRepeatedSpectrumCommand({
    required int freqHz,
    required int rbwHz,
    required int fftLen,
    required int count,
  }) {
    sendCommand('0x44 0x04 $freqHz $rbwHz $fftLen $count');
    _pendingDataType = Protocol.typeRepeatedSpectrum;
    _pendingDataSize = fftLen * 4;
  }

  /// Request IQ capture (single shot)
  /// Protocol: 0x44 0x02 <freq_hz> <rbw_hz> <iq_byte_size>
  void sendIqCaptureCommand({
    required int freqHz,
    required int rbwHz,
    required int iqByteSize,
  }) {
    sendCommand('0x44 0x02 $freqHz $rbwHz $iqByteSize');
    _pendingDataType = Protocol.typeIqCapture;
    _pendingDataSize = iqByteSize;
  }

  /// Request device status query
  /// Protocol: 0x44 0x05
  void sendStatusQueryCommand() {
    sendCommand('0x44 0x05');
  }

  // Callbacks
  void _onConnected() {
    debugPrint('MQTT: Connected to $_brokerIp');
    _connectionState = ConnectionState.connected;
    notifyListeners();
  }

  void _onDisconnected() {
    debugPrint('MQTT: Disconnected');
    _connectionState = ConnectionState.disconnected;
    _isInitialized = false;
    notifyListeners();
  }

  void _onAutoReconnect() {
    debugPrint('MQTT: Auto reconnecting...');
    _connectionState = ConnectionState.connecting;
    notifyListeners();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (var msg in messages) {
      final topic = msg.topic;
      final pubMsg = msg.payload as MqttPublishMessage;
      final payload = Uint8List.fromList(pubMsg.payload.message);

      if (topic == Protocol.dataTopic) {
        // pact/data1 - text response
        _handleTextResponse(payload);
      } else if (topic == Protocol.data2Topic) {
        // pact/data2 - binary data
        _handleBinaryData(payload);
      }
    }
  }

  void _handleTextResponse(Uint8List data) {
    final responseStr = String.fromCharCodes(data);

    final parts = responseStr.trim().split(' ');
    if (parts.length < 2) return;
    if (parts.contains("0x51") || responseStr.contains("0x06 0x02") || responseStr.contains("0x06 0x01") || responseStr.contains("0x06 0x00")) return;

    debugPrint('MQTT RX: $responseStr');
    _addLog(MqttLogEntry(
      direction: 'RX',
      topic: Protocol.dataTopic,
      message: responseStr,
    ));

    try {
      final header = int.parse(parts[0]);

      // T-Sync ACQ responses: 0x45 <acq_cmd_type> ...
      if (header == Protocol.respHeader && parts.length >= 2) {
        final typeVal = int.parse(parts[1]);
        if (typeVal >= Protocol.acqInit && typeVal <= Protocol.acqSaveIq) {
          _handleTsyncResponse(typeVal, parts);
          return;
        }
      }

      // Support multiple response formats:
      // Format 1: "0x44 0xXX OK" or "0x44 0xXX FAIL"
      // Format 2: "0x45 <type> <status>" (e.g., "0x45 0 1")
      // Format 3 (repeated): "0x45 <type> <status> <current_iteration> <total_count>"
      // Format 4 (status): "0x45 0x05 <status_data...>"
      if (header == Protocol.cmdHeader && parts.length >= 3) {
        // Format 1: 0x44 0xXX OK/FAIL
        final type = int.parse(parts[1]);
        final statusStr = parts[2].toUpperCase();
        final isOk = statusStr == 'OK';

        // Broadcast register responses (sub-commands >= 0x10, or 0x08 RF band ctrl) to register stream
        if (type >= 0x10 || type == Protocol.typeRfBandCtrl) {
          _registerResponseController.add(RegisterResponse(
            subCommand: type,
            params: parts.sublist(2),
            rawResponse: responseStr,
          ));
          return;
        }

        _processResponse(type, isOk);
      } else if (header == Protocol.respHeader && parts.length >= 3) {
        final type = int.parse(parts[1]);

        // Broadcast register responses (sub-commands >= 0x10, or 0x08 RF band ctrl) to register stream
        if (type >= 0x10 || type == Protocol.typeRfBandCtrl) {
          _registerResponseController.add(RegisterResponse(
            subCommand: type,
            params: parts.sublist(2),
            rawResponse: responseStr,
          ));
          // Don't process through normal pipeline
          if (type != Protocol.typeStatusQuery) return;
        }

        // Check if this is a status query response (Format 4)
        if (type == Protocol.typeStatusQuery && parts.length >= 24) {
          // Status query response contains full device status
          _statusController.add(responseStr);
          return;
        }

        final statusValue = int.parse(parts[2]);
        bool isOk;

        // Handle different response formats:
        // - If statusValue is large (>100), it's likely a data_size field, not status
        //   (e.g., "0x45 1 8192" = success with 8192 FFT points)
        // - If statusValue is small (<=10), it's a status code (1=success, 0=fail)
        if (statusValue > 100) {
          // This is likely "0x45 <type> <data_size>" format for Single FFT
          // Treat as success
          isOk = true;
        } else {
          // This is "0x45 <type> <status>" format
          isOk = statusValue == 1; // 1 = success
        }

        if (parts.length >= 5) {
          // Format 3: includes iteration info
          final currentIter = int.parse(parts[3]);
          final totalCount = int.parse(parts[4]);
          _processResponse(type, isOk, currentIter: currentIter, totalCount: totalCount);
        } else {
          // Format 2: legacy format or data_size format
          _processResponse(type, isOk);
        }
      }
    } catch (e) {
      debugPrint('Error parsing response: $e');
    }
  }

  // ── T-Sync ACQ response handler ──────────────────────────────────────────

  void _handleTsyncResponse(int typeVal, List<String> parts) {
    final field2 = parts.length >= 3 ? int.tryParse(parts[2]) : null;

    // Negative field2 → error code (-1 internal, -2 timeout, -3 unsupported)
    if (field2 != null && field2 < 0) {
      debugPrint('[MQTT] ACQ error cmd=0x${typeVal.toRadixString(16)} code=$field2');
      _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: false, params: parts));
      return;
    }

    switch (typeVal) {
      case Protocol.acqRun:
        // field2==0: start notify  field2==1: completion result
        if (field2 == 0) {
          _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: true, params: parts));
        } else {
          // Always emit completion ACK so _tsyncRunning is cleared regardless of parse result
          _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: true, params: parts));
          final result = TsyncIterResult.fromRunTokens(parts);
          if (result != null) _tsyncIterController.add(result);
        }

      case Protocol.acqLoop:
        // field2==0: loop start  field2==1: per-iter result  field2==2: loop end
        if (field2 == 0 || field2 == 2) {
          _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: true, params: parts));
        } else {
          final result = TsyncIterResult.fromLoopTokens(parts);
          if (result != null) _tsyncIterController.add(result);
        }

      case Protocol.acqStatus:
        final status = TsyncStatus.fromTokens(parts);
        if (status != null) _tsyncStatusController.add(status);

      case Protocol.acqResult:
        final result = TsyncAcqResult.fromTokens(parts);
        if (result != null) _tsyncAcqResultController.add(result);

      case Protocol.acqRunOne:
        // 0x45 0x6B <result_code>
        _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: field2 != null && field2 >= 0, params: parts));

      default:
        // ACK: acqInit/acqParam/acqStop/acqSetRf/acqSetPd/acqVersion/acqSaveIq
        _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: field2 != null && field2 >= 0, params: parts));
    }
  }

  // ── T-Sync ACQ send methods ───────────────────────────────────────────────

  /// 0x44 0x69 — version query
  void sendAcqVersion() => sendCommand('0x44 0x69');

  /// 0x44 0x60 — initialize ACQ
  void sendAcqInit() => sendCommand('0x44 0x60');

  /// 0x44 0x61 <mode> <samples> <ho_time> <dac> — set parameters
  void sendAcqParam({
    required int mode,
    required int samples,
    required int hoTime,
    required int dac,
  }) => sendCommand('0x44 0x61 $mode $samples $hoTime $dac');

  /// 0x44 0x62 <iterations> — run N iterations
  void sendAcqRun(int iterations) => sendCommand('0x44 0x62 $iterations');

  /// 0x44 0x65 <count> <delay_ms> — loop (0=infinite)
  void sendAcqLoop({required int count, required int delayMs}) =>
      sendCommand('0x44 0x65 $count $delayMs');

  /// 0x44 0x66 — stop loop
  void sendAcqStop() => sendCommand('0x44 0x66');

  /// 0x44 0x63 — query status
  void sendAcqStatus() => sendCommand('0x44 0x63');

  /// 0x44 0x64 — query detailed result
  void sendAcqResult() => sendCommand('0x44 0x64');

  /// 0x44 0x67 <ssb_off> <pd_off> <atten> — RF offset settings
  void sendAcqSetRf({
    required int ssbOff,
    required int pdOff,
    required int atten,
  }) => sendCommand('0x44 0x67 $ssbOff $pdOff $atten');

  /// 0x44 0x68 <thres_max> <thres_min> <beam> — PD threshold settings
  void sendAcqSetPd({
    required int thresMax,
    required int thresMin,
    required int beam,
  }) => sendCommand('0x44 0x68 $thresMax $thresMin $beam');

  /// 0x44 0x6A <enable> — saveiq (0=off, 1=on, 2=query)
  void sendAcqSaveIq(int enable) => sendCommand('0x44 0x6A $enable');
  @override
  void sendAcqRunOne() => sendCommand('0x44 0x6B');

  @override
  void sendRfBandCtrl(int path) => sendCommand('0x44 0x08 $path');

  // ── PL commands (0x70-0x75) ───────────────────────────────────────────────
  @override void sendPlInit()          => sendCommand('0x44 0x70');
  @override void sendPllSet(int data)  => sendCommand('0x44 0x71 $data');
  @override void sendPlStatus()        => sendCommand('0x44 0x72');
  @override void sendPllLocked()       => sendCommand('0x44 0x73');
  @override void sendFpgaTemp()        => sendCommand('0x44 0x74');
  @override void sendRfPwr(int enable) => sendCommand('0x44 0x75 $enable');

  // ─────────────────────────────────────────────────────────────────────────

  void _processResponse(int type, bool isOk, {int? currentIter, int? totalCount}) {
    if (type == Protocol.typeInit) {
      if (isOk) {
        _isInitialized = true;
        notifyListeners();
      }
    } else if (type == Protocol.typeSpectrum || type == Protocol.typeRepeatedSpectrum) {
      if (isOk) {
        _pendingDataType = type;

        // If this is the last iteration of repeated spectrum, reset pending type after data
        if (type == Protocol.typeRepeatedSpectrum &&
            currentIter != null &&
            totalCount != null &&
            currentIter >= totalCount) {
          // Will be reset in _handleBinaryData after receiving last data
          _pendingDataType = Protocol.typeSpectrum; // Use spectrum type to trigger reset
        }
      }
    } else if (type == Protocol.typeIqCapture) {
      if (isOk) {
        _pendingDataType = Protocol.typeIqCapture;
      }
    }

    final response = MqttResponse(
      type: type,
      status: isOk ? Protocol.statusOk : Protocol.statusError,
      isSuccess: isOk,
      currentIteration: currentIter,
      totalCount: totalCount,
    );

    _responseController.add(response);
  }

  void _handleBinaryData(Uint8List data) {
    debugPrint('MQTT RX: Binary data ${data.length} bytes on ${Protocol.data2Topic}');
    _addLog(MqttLogEntry(
      direction: 'RX',
      topic: Protocol.data2Topic,
      message: '${data.length} bytes',
      isBinary: true,
    ));

    if (_pendingDataType == Protocol.typeSpectrum || _pendingDataType == Protocol.typeRepeatedSpectrum) {
      _spectrumDataController.add(data);
      // For repeated spectrum, don't reset pending type (more data coming)
      if (_pendingDataType == Protocol.typeSpectrum) {
        _pendingDataType = -1;
      }
    } else if (_pendingDataType == Protocol.typeIqCapture) {
      _iqDataController.add(data);
      _pendingDataType = -1;
    }
  }

  @override
  void dispose() {
    _client?.disconnect();
    _responseController.close();
    _spectrumDataController.close();
    _iqDataController.close();
    _logController.close();
    _statusController.close();
    _registerResponseController.close();
    _tsyncIterController.close();
    _tsyncStatusController.close();
    _tsyncAcqResultController.close();
    _tsyncAckController.close();
    super.dispose();
  }
}

