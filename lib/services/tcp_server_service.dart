import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../constants/protocol.dart';
import '../models/tsync_data.dart';
import 'mqtt_service.dart';
import 'transport_service.dart';

/// TCP Server transport.
///
/// Flutter acts as the server; the Linux device connects as a client.
///
/// Wire format (host byte order = little-endian):
///   [magic 4B LE][type 1B][pad 3B][length 4B LE][payload]
///
/// Received frame types:
///   0x01 TCP_TYPE_STR_RESP  — text response → _handleTextResponse()
///   0x02 TCP_TYPE_BIN_DATA  — binary data   → _handleBinaryData()
///
/// Sent frame type:
///   0x10 TCP_TYPE_CMD       — command string
class TcpServerService extends TransportService {
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  StreamSubscription? _clientSubscription;

  ConnectionState _connectionState = ConnectionState.disconnected;
  String _lastError = '';
  String _clientIp = '';
  bool _isInitialized = false;
  int _listenPort = Protocol.tcpServerPort;

  // Receive buffer for frame reassembly
  final List<int> _recvBuffer = [];

  // Pending binary data type (-1 = none)
  int _pendingDataType = -1;

  // Stream controllers (same set as MqttService)
  final _responseController        = StreamController<MqttResponse>.broadcast();
  final _spectrumDataController    = StreamController<Uint8List>.broadcast();
  final _iqDataController          = StreamController<Uint8List>.broadcast();
  final _logController             = StreamController<MqttLogEntry>.broadcast();
  final _statusController          = StreamController<String>.broadcast();
  final _registerResponseController = StreamController<RegisterResponse>.broadcast();

  final _tsyncIterController       = StreamController<TsyncIterResult>.broadcast();
  final _tsyncStatusController     = StreamController<TsyncStatus>.broadcast();
  final _tsyncAcqResultController  = StreamController<TsyncAcqResult>.broadcast();
  final _tsyncAckController        = StreamController<TsyncAck>.broadcast();

  final List<MqttLogEntry> _logHistory = [];
  static const int _maxLogEntries = 500;

  // ── Getters ─────────────────────────────────────────────────────────────────
  @override ConnectionState get connectionState  => _connectionState;
  @override String          get lastError        => _lastError;
  @override String          get brokerIp         => _clientIp;  // client IP for FTP
  @override bool            get isConnected      => _connectionState == ConnectionState.connected;
  @override bool            get isInitialized    => _isInitialized;
  @override List<MqttLogEntry> get logHistory    => List.unmodifiable(_logHistory);

  int get listenPort => _listenPort;

  @override Stream<MqttResponse>     get responseStream           => _responseController.stream;
  @override Stream<Uint8List>        get spectrumDataStream       => _spectrumDataController.stream;
  @override Stream<Uint8List>        get iqDataStream             => _iqDataController.stream;
  @override Stream<MqttLogEntry>     get logStream                => _logController.stream;
  @override Stream<String>           get statusStream             => _statusController.stream;
  @override Stream<RegisterResponse> get registerResponseStream   => _registerResponseController.stream;
  @override Stream<TsyncIterResult>  get tsyncIterStream          => _tsyncIterController.stream;
  @override Stream<TsyncStatus>      get tsyncStatusStream        => _tsyncStatusController.stream;
  @override Stream<TsyncAcqResult>   get tsyncAcqResultStream     => _tsyncAcqResultController.stream;
  @override Stream<TsyncAck>         get tsyncAckStream           => _tsyncAckController.stream;

  // ── Logging ──────────────────────────────────────────────────────────────────
  void _addLog(MqttLogEntry entry) {
    _logHistory.add(entry);
    if (_logHistory.length > _maxLogEntries) _logHistory.removeAt(0);
    _logController.add(entry);
    notifyListeners();
  }

  @override
  void clearLogs() {
    _logHistory.clear();
    notifyListeners();
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  /// [address] is the listen port as a string (e.g. "9000").
  @override
  Future<bool> connect(String address) async {
    if (_connectionState == ConnectionState.connecting ||
        _connectionState == ConnectionState.connected) {
      return false;
    }

    _listenPort = int.tryParse(address) ?? Protocol.tcpServerPort;
    _lastError = '';
    _connectionState = ConnectionState.connecting;
    notifyListeners();

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _listenPort,
        shared: true,
      );

      _addLog(MqttLogEntry(
        direction: 'SYS',
        topic: '',
        message: 'Listening on port $_listenPort — waiting for device...',
      ));

      // Accept exactly one client; subsequent connections replace the existing one.
      _serverSocket!.listen(_onClientConnected, onError: (e) {
        _lastError = e.toString();
        _connectionState = ConnectionState.error;
        notifyListeners();
      });

      return true;
    } catch (e) {
      _lastError = e.toString();
      _connectionState = ConnectionState.error;
      notifyListeners();
      return false;
    }
  }

  void _onClientConnected(Socket client) {
    // Drop any existing client
    _clientSubscription?.cancel();
    _clientSocket?.destroy();

    _clientSocket = client;
    _clientIp = client.remoteAddress.address;
    _recvBuffer.clear();

    _connectionState = ConnectionState.connected;
    _addLog(MqttLogEntry(
      direction: 'SYS',
      topic: '',
      message: 'Device connected from $_clientIp',
    ));

    _clientSubscription = client.listen(
      _onData,
      onError: (e) {
        debugPrint('[TCP] client error: $e');
        _onClientDisconnected();
      },
      onDone: _onClientDisconnected,
    );
  }

  void _onClientDisconnected() {
    _clientSocket?.destroy();
    _clientSocket = null;
    _clientSubscription?.cancel();
    _clientSubscription = null;
    _recvBuffer.clear();
    _isInitialized = false;

    // Stay in connecting state (still listening) if server socket is alive.
    if (_serverSocket != null) {
      _connectionState = ConnectionState.connecting;
      _addLog(MqttLogEntry(
        direction: 'SYS',
        topic: '',
        message: 'Device disconnected — waiting for reconnect on port $_listenPort...',
      ));
    } else {
      _connectionState = ConnectionState.disconnected;
    }
    notifyListeners();
  }

  @override
  void disconnect() {
    _clientSubscription?.cancel();
    _clientSubscription = null;
    _clientSocket?.destroy();
    _clientSocket = null;
    _serverSocket?.close();
    _serverSocket = null;
    _recvBuffer.clear();
    _isInitialized = false;
    _connectionState = ConnectionState.disconnected;
    _addLog(MqttLogEntry(direction: 'SYS', topic: '', message: 'Server stopped'));
    notifyListeners();
  }

  // ── Frame reception ──────────────────────────────────────────────────────────

  static const int _headerSize = Protocol.tcpHeaderSize;  // 12 bytes
  static const int _magic      = Protocol.tcpMagic;       // 0xABCD1234 LE

  void _onData(Uint8List data) {
    _recvBuffer.addAll(data);
    _parseFrames();
  }

  void _parseFrames() {
    while (_recvBuffer.length >= _headerSize) {
      final buf = Uint8List.fromList(_recvBuffer);
      final view = ByteData.sublistView(buf);

      // Check magic (little-endian uint32)
      final magic = view.getUint32(0, Endian.little);
      if (magic != _magic) {
        // Out of sync — discard one byte and retry
        _recvBuffer.removeAt(0);
        continue;
      }

      final type   = buf[4];
      // pad: bytes 5,6,7 — ignored
      final length = view.getUint32(8, Endian.little);

      if (_recvBuffer.length < _headerSize + length) break; // wait for more bytes

      final payload = Uint8List.fromList(
        _recvBuffer.sublist(_headerSize, _headerSize + length),
      );
      _recvBuffer.removeRange(0, _headerSize + length);

      _dispatchFrame(type, payload);
    }
  }

  void _dispatchFrame(int type, Uint8List payload) {
    switch (type) {
      case Protocol.tcpTypeStrResp:
        _handleTextResponse(payload);
      case Protocol.tcpTypeBinData:
        _handleBinaryData(payload);
      default:
        debugPrint('[TCP] unknown frame type: 0x${type.toRadixString(16)}');
    }
  }

  // ── Text / binary handlers (same logic as MqttService) ──────────────────────

  /// magic number in the firmware READY ping: "0x200000 <runmode>"
  static const int _readyPingHdr = 0x200000;

  /// Returns all non-loopback IPv4 addresses of this machine.
  static Future<List<String>> getLocalIpAddresses() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final iface in ifaces)
          for (final addr in iface.addresses)
            if (!addr.isLoopback) addr.address,
      ];
    } catch (_) {
      return [];
    }
  }

  void _handleTextResponse(Uint8List data) {
    final responseStr = String.fromCharCodes(data);
    final parts = responseStr.trim().split(' ');
    if (parts.isEmpty) return;

    // ── READY ping: "0x200000 <runmode>" ─────────────────────────────────────
    // Sent by the firmware immediately after TCP connection is established.
    try {
      if (int.parse(parts[0]) == _readyPingHdr) {
        final runmode = parts.length >= 2 ? parts[1] : '?';
        debugPrint('[TCP] Device READY ping — runmode=$runmode');
        _addLog(MqttLogEntry(
          direction: 'SYS',
          topic: '',
          message: 'Device READY (runmode=$runmode)',
        ));
        return;
      }
    } catch (_) {}

    if (parts.length < 2) return;
    if (parts.contains('0x51') ||
        responseStr.contains('0x06 0x02') ||
        responseStr.contains('0x06 0x01')) return;

    debugPrint('[TCP] RX: $responseStr');
    _addLog(MqttLogEntry(
      direction: 'RX',
      topic: 'tcp',
      message: responseStr,
    ));

    try {
      final header = int.parse(parts[0]);

      if (header == Protocol.respHeader && parts.length >= 2) {
        final typeVal = int.parse(parts[1]);
        if (typeVal >= Protocol.acqInit && typeVal <= Protocol.acqSaveIq) {
          _handleTsyncResponse(typeVal, parts);
          return;
        }
      }

      if (header == Protocol.cmdHeader && parts.length >= 3) {
        final type = int.parse(parts[1]);
        final statusStr = parts[2].toUpperCase();
        final isOk = statusStr == 'OK';
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
        if (type >= 0x10) {
          _registerResponseController.add(RegisterResponse(
            subCommand: type,
            params: parts.sublist(2),
            rawResponse: responseStr,
          ));
          if (type != Protocol.typeStatusQuery) return;
        }
        if (type == Protocol.typeStatusQuery && parts.length >= 24) {
          _statusController.add(responseStr);
          return;
        }
        final statusValue = int.parse(parts[2]);
        final isOk = statusValue > 100 ? true : statusValue == 1;
        if (parts.length >= 5) {
          _processResponse(type, isOk,
              currentIter: int.parse(parts[3]),
              totalCount: int.parse(parts[4]));
        } else {
          _processResponse(type, isOk);
        }
      }
    } catch (e) {
      debugPrint('[TCP] error parsing response: $e');
    }
  }

  void _handleTsyncResponse(int typeVal, List<String> parts) {
    if (parts.length >= 3 && int.tryParse(parts[2]) == Protocol.acqRespError) {
      _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: false));
      return;
    }
    switch (typeVal) {
      case Protocol.acqRun:
      case Protocol.acqLoop:
        final result = TsyncIterResult.fromTokens(parts);
        if (result != null) _tsyncIterController.add(result);
      case Protocol.acqStatus:
        final status = TsyncStatus.fromTokens(parts);
        if (status != null) _tsyncStatusController.add(status);
      case Protocol.acqResult:
        final result = TsyncAcqResult.fromTokens(parts);
        if (result != null) _tsyncAcqResultController.add(result);
      default:
        final isOk = parts.length >= 3 &&
            int.tryParse(parts[2]) != Protocol.acqRespError;
        _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: isOk, params: parts));
    }
  }

  void _processResponse(int type, bool isOk,
      {int? currentIter, int? totalCount}) {
    if (type == Protocol.typeInit && isOk) {
      _isInitialized = true;
      notifyListeners();
    } else if ((type == Protocol.typeSpectrum ||
            type == Protocol.typeRepeatedSpectrum) &&
        isOk) {
      _pendingDataType = type;
      if (type == Protocol.typeRepeatedSpectrum &&
          currentIter != null &&
          totalCount != null &&
          currentIter >= totalCount) {
        _pendingDataType = Protocol.typeSpectrum;
      }
    } else if (type == Protocol.typeIqCapture && isOk) {
      _pendingDataType = Protocol.typeIqCapture;
    }

    _responseController.add(MqttResponse(
      type: type,
      status: isOk ? Protocol.statusOk : Protocol.statusError,
      isSuccess: isOk,
      currentIteration: currentIter,
      totalCount: totalCount,
    ));
  }

  void _handleBinaryData(Uint8List data) {
    debugPrint('[TCP] RX binary: ${data.length} bytes');
    _addLog(MqttLogEntry(
      direction: 'RX',
      topic: 'tcp-bin',
      message: '${data.length} bytes',
      isBinary: true,
    ));

    if (_pendingDataType == Protocol.typeSpectrum ||
        _pendingDataType == Protocol.typeRepeatedSpectrum) {
      _spectrumDataController.add(data);
      if (_pendingDataType == Protocol.typeSpectrum) _pendingDataType = -1;
    } else if (_pendingDataType == Protocol.typeIqCapture) {
      _iqDataController.add(data);
      _pendingDataType = -1;
    }
  }

  // ── Frame builder & sender ───────────────────────────────────────────────────

  void _sendFrame(int type, Uint8List payload) {
    final client = _clientSocket;
    if (client == null) return;

    final header = ByteData(_headerSize);
    header.setUint32(0, _magic, Endian.little);
    header.setUint8(4, type);
    // bytes 5,6,7 = padding (0)
    header.setUint32(8, payload.length, Endian.little);

    client.add(header.buffer.asUint8List());
    client.add(payload);
  }

  // ── TransportService commands ─────────────────────────────────────────────────

  @override
  void sendCommand(String command) {
    if (!isConnected) {
      debugPrint('[TCP] Not connected, cannot send command');
      return;
    }
    final payload = Uint8List.fromList(command.codeUnits);
    _sendFrame(Protocol.tcpTypeCmdReq, payload);

    debugPrint('[TCP] TX: $command');
    _addLog(MqttLogEntry(direction: 'TX', topic: 'tcp', message: command));
  }

  @override void sendInitCommand()  => sendCommand('0x44 0x00');

  @override
  void sendSpectrumCommand({required int freqHz, required int rbwHz, int fftLen = 8192}) {
    sendCommand('0x44 0x01 $freqHz $rbwHz $fftLen');
    _pendingDataType = Protocol.typeSpectrum;
  }

  @override
  void sendRepeatedSpectrumCommand({
    required int freqHz,
    required int rbwHz,
    required int fftLen,
    required int count,
  }) {
    sendCommand('0x44 0x04 $freqHz $rbwHz $fftLen $count');
    _pendingDataType = Protocol.typeRepeatedSpectrum;
  }

  @override
  void sendIqCaptureCommand({
    required int freqHz,
    required int rbwHz,
    required int iqByteSize,
  }) {
    sendCommand('0x44 0x02 $freqHz $rbwHz $iqByteSize');
    _pendingDataType = Protocol.typeIqCapture;
  }

  @override void sendStatusQueryCommand() => sendCommand('0x44 0x05');

  @override void sendAcqVersion()  => sendCommand('0x44 0x69');
  @override void sendAcqInit()     => sendCommand('0x44 0x60');
  @override void sendAcqStop()     => sendCommand('0x44 0x66');
  @override void sendAcqStatus()   => sendCommand('0x44 0x63');
  @override void sendAcqResult()   => sendCommand('0x44 0x64');
  @override void sendAcqRun(int iterations) => sendCommand('0x44 0x62 $iterations');
  @override void sendAcqSaveIq(int enable)  => sendCommand('0x44 0x6A $enable');

  @override
  void sendAcqParam({required int mode, required int samples, required int hoTime, required int dac}) =>
      sendCommand('0x44 0x61 $mode $samples $hoTime $dac');

  @override
  void sendAcqLoop({required int count, required int delayMs}) =>
      sendCommand('0x44 0x65 $count $delayMs');

  @override
  void sendAcqSetRf({required int ssbOff, required int pdOff, required int atten}) =>
      sendCommand('0x44 0x67 $ssbOff $pdOff $atten');

  @override
  void sendAcqSetPd({required int thresMax, required int thresMin, required int beam}) =>
      sendCommand('0x44 0x68 $thresMax $thresMin $beam');

  // ── dispose ──────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _clientSubscription?.cancel();
    _clientSocket?.destroy();
    _serverSocket?.close();
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
