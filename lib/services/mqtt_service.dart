import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart' hide Protocol;
import 'package:mqtt_client/mqtt_server_client.dart';
import '../constants/protocol.dart';

enum ConnectionState { disconnected, connecting, connected, error }

/// MQTT log entry for display
class MqttLogEntry {
  final DateTime timestamp;
  final String direction; // 'TX' or 'RX'
  final String topic;
  final String message;
  final bool isBinary;

  MqttLogEntry({
    required this.direction,
    required this.topic,
    required this.message,
    this.isBinary = false,
  }) : timestamp = DateTime.now();

  String get formattedTime =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}.'
      '${timestamp.millisecond.toString().padLeft(3, '0')}';
}

/// MQTT Service for communication with Combo FW
class MqttService extends ChangeNotifier {
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
    if (parts.contains("0x51") || responseStr.contains("0x06 0x02") || responseStr.contains("0x06 0x01")) return;

    debugPrint('MQTT RX: $responseStr');
    _addLog(MqttLogEntry(
      direction: 'RX',
      topic: Protocol.dataTopic,
      message: responseStr,
    ));

    try {
      final header = int.parse(parts[0]);

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

        // Broadcast register responses (sub-commands >= 0x10) to register stream
        if (type >= 0x10) {
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

        // Broadcast register responses (sub-commands >= 0x10) to register stream
        if (type >= 0x10) {
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
    super.dispose();
  }
}

/// MQTT Response data
class MqttResponse {
  final int type;
  final int status;
  final bool isSuccess;
  final int? currentIteration;
  final int? totalCount;

  MqttResponse({
    required this.type,
    required this.status,
    required this.isSuccess,
    this.currentIteration,
    this.totalCount,
  });

  bool get isOk => isSuccess;
  String get statusMessage => isSuccess ? 'OK' : 'FAIL';
}

/// Register response for sub-commands 0x10-0x4F
class RegisterResponse {
  final int subCommand;
  final List<String> params;
  final String rawResponse;

  RegisterResponse({
    required this.subCommand,
    required this.params,
    required this.rawResponse,
  });
}
