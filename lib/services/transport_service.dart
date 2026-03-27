import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../constants/protocol.dart';
import '../models/tsync_data.dart';

// ── Shared types ──────────────────────────────────────────────────────────────

enum ConnectionState { disconnected, connecting, connected, error }

/// Log entry displayed in the MQTT/transport log panel.
class MqttLogEntry {
  final DateTime timestamp;
  final String direction; // 'TX', 'RX', or 'SYS'
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

/// Response decoded from a device text message.
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

/// ACK event for tsync simple responses (acqInit, acqParam, acqStop, etc.)
class TsyncAck {
  final int cmd;
  final bool isOk;
  final List<String> params;

  TsyncAck({required this.cmd, required this.isOk, this.params = const []});
}

/// Register response for sub-commands 0x10-0x4F.
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

// ── Abstract transport interface ───────────────────────────────────────────────

/// Abstract transport layer — implemented by [MqttService] and [TcpServerService].
abstract class TransportService extends ChangeNotifier {
  ConnectionState get connectionState;
  String get lastError;

  /// For MQTT: broker IP.  For TCP Server: connected client's IP (used for FTP).
  String get brokerIp;

  bool get isConnected;
  bool get isInitialized;
  List<MqttLogEntry> get logHistory;

  // ── Data streams ─────────────────────────────────────────────────────────────
  Stream<MqttResponse>     get responseStream;
  Stream<Uint8List>        get spectrumDataStream;
  Stream<Uint8List>        get iqDataStream;
  Stream<MqttLogEntry>     get logStream;
  Stream<String>           get statusStream;
  Stream<RegisterResponse> get registerResponseStream;

  // T-Sync ACQ
  Stream<TsyncIterResult>  get tsyncIterStream;
  Stream<TsyncStatus>      get tsyncStatusStream;
  Stream<TsyncAcqResult>   get tsyncAcqResultStream;
  Stream<TsyncAck>         get tsyncAckStream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────
  /// MQTT: connect to broker at [address].
  /// TCP Server: start listening on port [address] (e.g. "9000").
  Future<bool> connect(String address);
  void disconnect();
  void clearLogs();

  // ── Commands ──────────────────────────────────────────────────────────────────
  void sendCommand(String command);
  void sendInitCommand();
  void sendSpectrumCommand({required int freqHz, required int rbwHz, int fftLen = 8192});
  void sendRepeatedSpectrumCommand({
    required int freqHz,
    required int rbwHz,
    required int fftLen,
    required int count,
  });
  void sendIqCaptureCommand({
    required int freqHz,
    required int rbwHz,
    required int iqByteSize,
  });
  void sendStatusQueryCommand();

  // T-Sync
  void sendAcqVersion();
  void sendAcqInit();
  void sendAcqParam({
    required int mode,
    required int samples,
    required int hoTime,
    required int dac,
  });
  void sendAcqRun(int iterations);
  void sendAcqLoop({required int count, required int delayMs});
  void sendAcqStop();
  void sendAcqStatus();
  void sendAcqResult();
  void sendAcqSetRf({required int ssbOff, required int pdOff, required int atten});
  void sendAcqSetPd({required int thresMax, required int thresMin, required int beam});
  void sendAcqSaveIq(int enable);
  void sendAcqRunOne(); // 0x6B — single one-shot run; result arrives via tsyncAckStream

  /// RF band path control (0x44 0x08 <path>).
  /// Response arrives via [registerResponseStream] as subCommand=0x08, params[0]=path_value.
  void sendRfBandCtrl(int path);

  // ── PL commands (0x70-0x75) ───────────────────────────────────────────────
  // All responses arrive via [registerResponseStream]; params[0] holds the return value.

  /// 0x70 pllinit — RF_PWR ON + ADF4001 4-latch init + lock poll.
  /// params[0]: "1" (success) / "0" (fail)
  void sendPlInit();

  /// 0x71 pllset <data> — write single 24-bit latch.
  /// params[0]: "0"
  void sendPllSet(int data);

  /// 0x72 plstatus — dump PL register status.
  /// params[0]: "0"
  void sendPlStatus();

  /// 0x73 plllocked — read ZYNQ_CLK_LOCKED.
  /// params[0]: "1" (locked) / "0" (unlocked)
  void sendPllLocked();

  /// 0x74 fpgatemp — read TMP102 temperature (blocking).
  /// params[0]: temperature in milli-degC, or timeout string
  void sendFpgaTemp();

  /// 0x75 rfpwr <0|1> — set RF_PWR.
  /// params[0]: current RF_PWR state after setting
  void sendRfPwr(int enable);
}
