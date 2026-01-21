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

  // Pending binary data info
  int _pendingDataType = -1;
  int _pendingDataSize = 0;

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
  void sendSpectrumCommand({int fftLen = Protocol.defaultFftLength}) {
    sendCommand('0x44 0x01 $fftLen');
    _pendingDataType = Protocol.typeSpectrum;
    _pendingDataSize = fftLen * 4;
  }

  /// Request IQ capture (single shot)
  void sendIqCaptureCommand({int sampleCount = 8192}) {
    sendCommand('0x44 0x02 $sampleCount');
    _pendingDataType = Protocol.typeIqCapture;
    _pendingDataSize = sampleCount * 4;
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
    if (parts.contains("0x51") || parts.contains("0x06 0x02") || parts.contains("0x06 0x01")) return;

    debugPrint('MQTT RX: $responseStr');
    _addLog(MqttLogEntry(
      direction: 'RX',
      topic: Protocol.dataTopic,
      message: responseStr,
    ));

    try {
      final header = int.parse(parts[0]);

      // Support both response formats:
      // New format: "0x44 0xXX OK" or "0x44 0xXX FAIL"
      // Legacy format: "0x45 <type> <status>" (e.g., "0x45 0 1")
      if (header == Protocol.cmdHeader && parts.length >= 3) {
        // New format: 0x44 0xXX OK/FAIL
        final type = int.parse(parts[1]);
        final statusStr = parts[2].toUpperCase();
        final isOk = statusStr == 'OK';

        _processResponse(type, isOk);
      } else if (header == Protocol.respHeader && parts.length >= 3) {
        // Legacy format: 0x45 <type> <status>
        // e.g., "0x45 0 1" means init success (type=0, status=1 means OK)
        final type = int.parse(parts[1]);
        final statusValue = int.parse(parts[2]);
        final isOk = statusValue == 1; // 1 = success

        _processResponse(type, isOk);
      }
    } catch (e) {
      debugPrint('Error parsing response: $e');
    }
  }

  void _processResponse(int type, bool isOk) {
    if (type == Protocol.typeInit) {
      if (isOk) {
        _isInitialized = true;
        notifyListeners();
      }
    } else if (type == Protocol.typeSpectrum) {
      if (isOk) {
        _pendingDataType = Protocol.typeSpectrum;
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

    if (_pendingDataType == Protocol.typeSpectrum) {
      _spectrumDataController.add(data);
    } else if (_pendingDataType == Protocol.typeIqCapture) {
      _iqDataController.add(data);
    }

    _pendingDataType = -1;
  }

  @override
  void dispose() {
    _client?.disconnect();
    _responseController.close();
    _spectrumDataController.close();
    _iqDataController.close();
    _logController.close();
    super.dispose();
  }
}

/// MQTT Response data
class MqttResponse {
  final int type;
  final int status;
  final bool isSuccess;

  MqttResponse({
    required this.type,
    required this.status,
    required this.isSuccess,
  });

  bool get isOk => isSuccess;
  String get statusMessage => isSuccess ? 'OK' : 'FAIL';
}
