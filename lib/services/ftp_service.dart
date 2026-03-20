import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/protocol.dart';

enum FtpDownloadState { idle, connecting, downloading, done, error }

class FtpDownloadResult {
  final int fileCounter;
  final List<int> iData; // ACQ_I values (int16 per line)
  final List<int> qData; // ACQ_Q values (int16 per line)

  const FtpDownloadResult({
    required this.fileCounter,
    required this.iData,
    required this.qData,
  });
}

/// Minimal FTP client for downloading ACQ_I/ACQ_Q text files.
/// Uses active-mode / passive-mode FTP over raw Socket (dart:io).
class FtpService {
  final String host;
  final int port;

  FtpService({required this.host, this.port = Protocol.ftpPort});

  /// Download ACQ_I_XXXX.txt and ACQ_Q_XXXX.txt for [fileCounter].
  /// Returns [FtpDownloadResult] or throws on error.
  Future<FtpDownloadResult> downloadIqFiles(int fileCounter) async {
    final counterStr = fileCounter.toString().padLeft(4, '0');
    final iFile = 'ACQ_I_$counterStr.txt';
    final qFile = 'ACQ_Q_$counterStr.txt';
    final remotePath = Protocol.ftpRemoteBase;

    final iData = await _downloadFile('$remotePath/$iFile');
    final qData = await _downloadFile('$remotePath/$qFile');

    return FtpDownloadResult(
      fileCounter: fileCounter,
      iData: iData,
      qData: qData,
    );
  }

  /// Download a single text file via FTP passive mode.
  /// Returns each line parsed as int.
  Future<List<int>> _downloadFile(String remotePath) async {
    Socket? control;
    Socket? data;

    try {
      control = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));
      control.encoding = const SystemEncoding();

      final reader = _FtpLineReader(control);

      // Read greeting
      await reader.readResponse();

      // Login anonymous
      control.write('USER anonymous\r\n');
      await reader.readResponse();
      control.write('PASS anonymous@\r\n');
      await reader.readResponse();

      // Binary type
      control.write('TYPE I\r\n');
      await reader.readResponse();

      // Passive mode
      control.write('PASV\r\n');
      final pasvLine = await reader.readResponse();
      final dataAddr = _parsePasv(pasvLine);
      if (dataAddr == null) throw Exception('Failed to parse PASV response');

      // Open data connection
      data = await Socket.connect(dataAddr.$1, dataAddr.$2,
          timeout: const Duration(seconds: 10));

      // Request file
      control.write('RETR $remotePath\r\n');
      final retrResp = await reader.readResponse();
      if (!retrResp.startsWith('1')) {
        throw Exception('RETR failed: $retrResp');
      }

      // Read data
      final buffer = <int>[];
      final completer = Completer<void>();
      data.listen(
        buffer.addAll,
        onDone: completer.complete,
        onError: (e) => completer.completeError(e),
        cancelOnError: true,
      );
      await completer.future;
      await data.close();
      data = null;

      // Read transfer complete response
      await reader.readResponse();

      control.write('QUIT\r\n');
      await control.close();
      control = null;

      // Parse lines as int16
      final text = String.fromCharCodes(buffer);
      final values = <int>[];
      for (final line in text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final val = int.tryParse(trimmed);
        if (val != null) values.add(val);
      }
      return values;
    } finally {
      data?.destroy();
      control?.destroy();
    }
  }

  /// Parse PASV response: "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)"
  (String, int)? _parsePasv(String line) {
    final match = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)').firstMatch(line);
    if (match == null) return null;
    final ip = '${match[1]}.${match[2]}.${match[3]}.${match[4]}';
    final port = int.parse(match[5]!) * 256 + int.parse(match[6]!);
    return (ip, port);
  }
}

/// Reads FTP response lines (may be multi-line continuations).
class _FtpLineReader {
  final Socket _socket;
  final _buf = StringBuffer();
  final _lines = <String>[];
  StreamSubscription<List<int>>? _sub;
  Completer<String>? _pending;

  _FtpLineReader(this._socket) {
    _sub = _socket.listen((bytes) {
      _buf.write(String.fromCharCodes(bytes));
      _flush();
    });
  }

  void _flush() {
    final raw = _buf.toString();
    final parts = raw.split('\r\n');
    for (int i = 0; i < parts.length - 1; i++) {
      final line = parts[i];
      if (line.isNotEmpty) _lines.add(line);
    }
    _buf.clear();
    if (parts.last.isNotEmpty) _buf.write(parts.last);

    _tryResolve();
  }

  void _tryResolve() {
    if (_pending == null || _pending!.isCompleted) return;
    // FTP response ends when a line matches "NNN <text>" (with space after code)
    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.length >= 4 && line[3] == ' ' && int.tryParse(line.substring(0, 3)) != null) {
        final response = _lines.sublist(0, i + 1).join('\n');
        _lines.removeRange(0, i + 1);
        _pending!.complete(response);
        return;
      }
    }
  }

  Future<String> readResponse() {
    _pending = Completer<String>();
    _tryResolve();
    return _pending!.future.timeout(const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('FTP response timeout'));
  }

  void cancel() => _sub?.cancel();
}

/// Saves IQ data as CSV: columns iter, i, q
Future<void> saveIqCsv({
  required String filePath,
  required int fileCounter,
  required List<int> iData,
  required List<int> qData,
}) async {
  final sb = StringBuffer();
  sb.writeln('index,I,Q');
  final count = iData.length < qData.length ? iData.length : qData.length;
  for (int i = 0; i < count; i++) {
    sb.writeln('$i,${iData[i]},${qData[i]}');
  }
  final file = File(filePath);
  await file.writeAsString(sb.toString());
  debugPrint('[FTP] CSV saved: $filePath ($count samples)');
}
