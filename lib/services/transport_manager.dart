import 'package:flutter/foundation.dart';
import 'mqtt_service.dart';
import 'tcp_server_service.dart';
import 'transport_service.dart';

enum TransportMode { mqtt, tcpServer }

/// Holds both transport instances and tracks which is active.
///
/// Switching modes via [switchMode] disconnects the current transport
/// before activating the other one.
class TransportManager extends ChangeNotifier {
  final MqttService      mqttService;
  final TcpServerService tcpServerService;

  TransportMode _mode = TransportMode.mqtt;

  TransportManager({required this.mqttService, required this.tcpServerService}) {
    // Forward every state change from either service to our own listeners.
    // This ensures Consumer<TransportManager> widgets rebuild whenever
    // MqttService or TcpServerService calls notifyListeners()
    // (e.g. on connect, disconnect, isInitialized, log update).
    mqttService.addListener(notifyListeners);
    tcpServerService.addListener(notifyListeners);
  }

  TransportMode    get mode   => _mode;
  TransportService get active => _mode == TransportMode.mqtt ? mqttService : tcpServerService;

  void switchMode(TransportMode newMode) {
    if (_mode == newMode) return;
    active.disconnect();
    _mode = newMode;
    notifyListeners();
  }

  @override
  void dispose() {
    mqttService.removeListener(notifyListeners);
    tcpServerService.removeListener(notifyListeners);
    super.dispose();
  }
}
