import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../constants/protocol.dart';
import '../models/tsync_data.dart';
import 'mqtt_service.dart';
import 'transport_service.dart';

/// TCP Server transport (Refactored for Multi-Connection Support)
class TcpServerService extends TransportService {
  ServerSocket? _serverSocket;
  
  // Track all active client sockets
  final List<Socket> _activeSockets = [];
  
  // Use the most recently connected socket as the primary command channel
  Socket? get _clientSocket => _activeSockets.isNotEmpty ? _activeSockets.last : null;

  ConnectionState _connectionState = ConnectionState.disconnected;
  String _lastError = '';
  String _clientIp = '';
  bool _isInitialized = false;
  int _listenPort = Protocol.tcpServerPort;

  // Pending binary data type (-1 = none)
  int _pendingDataType = -1;

  // Stream controllers
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

  // Getters
  @override ConnectionState get connectionState  => _connectionState;
  @override String          get lastError        => _lastError;
  @override String          get brokerIp         => _clientIp;
  @override bool            get isConnected      => _activeSockets.isNotEmpty;
  @override bool            get isInitialized    => _isInitialized;
  @override List<MqttLogEntry> get logHistory    => List.unmodifiable(_logHistory);
  int get listenPort => _listenPort;

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

  @override
  Future<bool> connect(String address) async {
    if (_serverSocket != null) return true;

    _listenPort = int.tryParse(address) ?? Protocol.tcpServerPort;
    _connectionState = ConnectionState.connecting;
    notifyListeners();

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _listenPort, shared: true);
      _addLog(MqttLogEntry(direction: 'SYS', topic: '', message: 'Server listening on $_listenPort'));

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
    final port = client.remotePort;
    final address = client.remoteAddress.address;
    
    // debugPrint('[TCP] New connection: $address:$port');
    _activeSockets.add(client);
    _clientIp = address;
    _connectionState = ConnectionState.connected;
    
    _addLog(MqttLogEntry(direction: 'SYS', topic: '', message: 'Device connected (port $port)'));
    client.setOption(SocketOption.tcpNoDelay, true);

    // Each connection gets its own independent receive buffer
    final List<int> localBuffer = [];

    client.listen(
      (data) {
        // Detailed raw logging can be enabled for debugging
        final hex = data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
        // debugPrint('[TCP] Raw RX ($port, ${data.length} bytes): $hex');
        
        localBuffer.addAll(data);
        _parseFramesWithBuffer(localBuffer, client);
      },
      onError: (e) {
        // debugPrint('[TCP] Error on port $port: $e');
        _onClientDisconnected(client);
      },
      onDone: () {
        // debugPrint('[TCP] Port $port closed by peer');
        _onClientDisconnected(client);
      },
    );
    notifyListeners();
  }

  void _onClientDisconnected(Socket client) {
    final port = client.remotePort;
    // debugPrint('[TCP] Disconnected: $port');
    
    _activeSockets.remove(client);
    client.destroy();

    if (_activeSockets.isEmpty) {
      _connectionState = _serverSocket != null ? ConnectionState.connecting : ConnectionState.disconnected;
      _addLog(MqttLogEntry(direction: 'SYS', topic: '', message: 'All devices disconnected'));
    }
    notifyListeners();
  }

  @override
  void disconnect() {
    // Destroy all active clients
    for (var s in List.from(_activeSockets)) {
      s.destroy();
    }
    _activeSockets.clear();
    
    _serverSocket?.close();
    _serverSocket = null;
    _connectionState = ConnectionState.disconnected;
    _addLog(MqttLogEntry(direction: 'SYS', topic: '', message: 'Server stopped'));
    notifyListeners();
  }

  // ── Frame Parsing ───────────────────────────────────────────────────────────

  static const int _headerSize = Protocol.tcpHeaderSize;
  static const int _magic      = Protocol.tcpMagic;

  void _parseFramesWithBuffer(List<int> buffer, Socket socket) {
    const int maxPayloadLength = 10 * 1024 * 1024;

    while (buffer.length >= _headerSize) {
      final magic = buffer[0] | (buffer[1] << 8) | (buffer[2] << 16) | (buffer[3] << 24);

      if (magic != _magic) {
        int syncIndex = -1;
        for (int i = 1; i <= buffer.length - 4; i++) {
          final nextMagic = buffer[i] | (buffer[i+1] << 8) | (buffer[i+2] << 16) | (buffer[i+3] << 24);
          if (nextMagic == _magic) { syncIndex = i; break; }
        }
        if (syncIndex != -1) {
          // debugPrint('[TCP] Re-syncing buffer at index $syncIndex');
          buffer.removeRange(0, syncIndex);
        } else {
          buffer.clear();
          break;
        }
        continue;
      }

      final type   = buffer[4];
      final length = buffer[8] | (buffer[9] << 8) | (buffer[10] << 16) | (buffer[11] << 24);

      if (length > maxPayloadLength || length < 0) {
        // debugPrint('[TCP] Invalid length: $length');
        buffer.clear();
        break; 
      }

      if (buffer.length < _headerSize + length) break;

      final payload = Uint8List.fromList(buffer.sublist(_headerSize, _headerSize + length));
      buffer.removeRange(0, _headerSize + length);

      _dispatchFrame(type, payload, socket);
    }
  }

  void _dispatchFrame(int type, Uint8List payload, Socket socket) {
    switch (type) {
      case Protocol.tcpTypeStrResp:
        _handleTextResponse(payload, socket);
      case Protocol.tcpTypeBinData:
        _handleBinaryData(payload);
      default:
        // debugPrint('[TCP] Unknown frame 0x${type.toRadixString(16)}');
    }
  }

  // ── Handlers ────────────────────────────────────────────────────────────────

  static const int _readyPingHdr = 0x200000;

  void _handleTextResponse(Uint8List data, Socket socket) {
    final responseStr = String.fromCharCodes(data).trim();
    if (responseStr.isEmpty) return;

    final parts = responseStr.split(' ');
    
    // 1. Handshake & Automatic ACK logic for keeping device happy
    try {
      final headerInt = int.tryParse(parts[0]);
      if (headerInt != null) {
        // READY Ping (0x200000)
        if (headerInt == _readyPingHdr) {
          final runmode = parts.length >= 2 ? parts[1] : '?';
          _sendFrameTo(Protocol.tcpTypeCmdReq, Uint8List.fromList('0x200000 $runmode OK'.codeUnits), socket);
          _addLog(MqttLogEntry(direction: 'SYS', topic: '', message: 'Device READY ($runmode) — Handshake OK'));
          return;
        }
        
        // Heartbeat/Status ACK for specific headers (0x06, 0x51, 0x98)
        // if (headerInt == 0x06 || headerInt == 0x51 || headerInt == 0x98) {
        //   _sendFrameTo(Protocol.tcpTypeCmdReq, Uint8List.fromList('${parts[0]} OK'.codeUnits), socket);
        //   if (headerInt == 0x06 && responseStr.contains('0x06 0x02')) {
        //      // Keep status in logs
        //      _addLog(MqttLogEntry(direction: 'RX', topic: 'status', message: responseStr));
        //   }
        //   return;
        // }
      }
    } catch (_) {}

    // 2. Standard Response Parsing
    if (parts.length < 2) return;
    
    // debugPrint('[TCP] RX: $responseStr');
    _addLog(MqttLogEntry(direction: 'RX', topic: 'tcp', message: responseStr));

    try {
      final header = int.parse(parts[0]);

      if (header == Protocol.respHeader) {
        final typeVal = int.parse(parts[1]);
        if (typeVal >= Protocol.acqInit && typeVal <= Protocol.acqSaveIq) {
          _handleTsyncResponse(typeVal, parts);
          return;
        }
      }

      if (header == Protocol.cmdHeader || header == Protocol.respHeader) {
        final type = int.parse(parts[1]);
        if (type >= 0x10 || type == Protocol.typeRfBandCtrl || type == Protocol.typeStatusQuery) {
          _registerResponseController.add(RegisterResponse(
            subCommand: type,
            params: parts.sublist(2),
            rawResponse: responseStr,
          ));
          if (type == Protocol.typeStatusQuery && parts.length >= 24) {
            _statusController.add(responseStr);
          }
          if (type != Protocol.typeStatusQuery) _processResponse(type, true);
          return;
        }

        final bool isOk = parts.contains('OK') || (parts.length > 2 && int.tryParse(parts[2]) == 1);
        _processResponse(type, isOk, 
            currentIter: parts.length >= 4 ? int.tryParse(parts[3]) : null,
            totalCount: parts.length >= 5 ? int.tryParse(parts[4]) : null);
      }
    } catch (e) {
      // debugPrint('[TCP] Parse error: $e');
    }
  }

  void _handleTsyncResponse(int typeVal, List<String> parts) {
    final field2 = parts.length >= 3 ? int.tryParse(parts[2]) : null;
    if (field2 != null && field2 < 0) {
      _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: false, params: parts));
      return;
    }
    switch (typeVal) {
      case Protocol.acqRun:
        _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: true, params: parts));
        if (field2 != 0) {
          final result = TsyncIterResult.fromRunTokens(parts);
          if (result != null) _tsyncIterController.add(result);
        }
      case Protocol.acqLoop:
        _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: true, params: parts));
        if (field2 != 0 && field2 != 2) {
          final result = TsyncIterResult.fromLoopTokens(parts);
          if (result != null) _tsyncIterController.add(result);
        }
      case Protocol.acqStatus:
        final status = TsyncStatus.fromTokens(parts);
        if (status != null) _tsyncStatusController.add(status);
      case Protocol.acqResult:
        final result = TsyncAcqResult.fromTokens(parts);
        if (result != null) _tsyncAcqResultController.add(result);
      default:
        _tsyncAckController.add(TsyncAck(cmd: typeVal, isOk: field2 != null && field2 >= 0, params: parts));
    }
  }

  void _processResponse(int type, bool isOk, {int? currentIter, int? totalCount}) {
    if (type == Protocol.typeInit && isOk) _isInitialized = true;
    if (isOk && (type == Protocol.typeSpectrum || type == Protocol.typeRepeatedSpectrum)) {
      _pendingDataType = type;
      if (type == Protocol.typeRepeatedSpectrum && currentIter != null && totalCount != null && currentIter >= totalCount) {
        _pendingDataType = Protocol.typeSpectrum;
      }
    } else if (type == Protocol.typeIqCapture && isOk) {
      _pendingDataType = Protocol.typeIqCapture;
    }
    _responseController.add(MqttResponse(type: type, status: isOk ? 0 : 1, isSuccess: isOk, currentIteration: currentIter, totalCount: totalCount));
    notifyListeners();
  }

  void _handleBinaryData(Uint8List data) {
    _addLog(MqttLogEntry(direction: 'RX', topic: 'tcp-bin', message: '${data.length} bytes', isBinary: true));
    if (_pendingDataType == Protocol.typeSpectrum || _pendingDataType == Protocol.typeRepeatedSpectrum) {
      _spectrumDataController.add(data);
      if (_pendingDataType == Protocol.typeSpectrum) _pendingDataType = -1;
    } else if (_pendingDataType == Protocol.typeIqCapture) {
      _iqDataController.add(data);
      _pendingDataType = -1;
    }
  }

  // ── Frame Builder & Sender ──────────────────────────────────────────────────

  void _sendFrameTo(int type, Uint8List payload, Socket? target) {
    if (target == null) return;
    try {
      final header = ByteData(_headerSize);
      header.setUint32(0, _magic, Endian.little);
      header.setUint8(4, type);
      header.setUint32(8, payload.length, Endian.little);
      target.add(header.buffer.asUint8List());
      target.add(payload);
      target.flush();
    } catch (e) {
      // debugPrint('[TCP] Send error: $e');
    }
  }

  @override
  void sendCommand(String command) {
    final target = _clientSocket;
    if (target == null) {
      // debugPrint('[TCP] No client connected');
      return;
    }
    _sendFrameTo(Protocol.tcpTypeCmdReq, Uint8List.fromList(command.codeUnits), target);
    // debugPrint('[TCP] TX: $command');
    _addLog(MqttLogEntry(direction: 'TX', topic: 'tcp', message: command));
  }

  // ── Commands ────────────────────────────────────────────────────────────────
  @override void sendInitCommand()  => sendCommand('0x44 0x00');
  @override void sendSpectrumCommand({required int freqHz, required int rbwHz, int fftLen = 8192}) {
    sendCommand('0x44 0x01 $freqHz $rbwHz $fftLen');
    _pendingDataType = Protocol.typeSpectrum;
  }
  @override void sendRepeatedSpectrumCommand({required int freqHz, required int rbwHz, required int fftLen, required int count}) {
    sendCommand('0x44 0x04 $freqHz $rbwHz $fftLen $count');
    _pendingDataType = Protocol.typeRepeatedSpectrum;
  }
  @override void sendIqCaptureCommand({required int freqHz, required int rbwHz, required int iqByteSize}) {
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
  @override void sendAcqRunOne()            => sendCommand('0x44 0x6B');
  @override void sendAcqParam({required int mode, required int samples, required int hoTime, required int dac}) => sendCommand('0x44 0x61 $mode $samples $hoTime $dac');
  @override void sendAcqLoop({required int count, required int delayMs}) => sendCommand('0x44 0x65 $count $delayMs');
  @override void sendAcqSetRf({required int ssbOff, required int pdOff, required int atten}) => sendCommand('0x44 0x67 $ssbOff $pdOff $atten');
  @override void sendAcqSetPd({required int thresMax, required int thresMin, required int beam}) => sendCommand('0x44 0x68 $thresMax $thresMin $beam');
  @override void sendRfBandCtrl(int path) => sendCommand('0x44 0x08 $path');
  @override void sendPlInit()         => sendCommand('0x44 0x70');
  @override void sendPllSet(int data) => sendCommand('0x44 0x71 $data');
  @override void sendPlStatus()       => sendCommand('0x44 0x72');
  @override void sendPllLocked()      => sendCommand('0x44 0x73');
  @override void sendFpgaTemp()       => sendCommand('0x44 0x74');
  @override void sendRfPwr(int enable)=> sendCommand('0x44 0x75 $enable');

  @override
  void dispose() {
    disconnect();
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
