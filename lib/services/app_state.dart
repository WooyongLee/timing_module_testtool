import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants/protocol.dart';
import '../models/spectrum_data.dart';
import '../models/iq_data.dart';
import '../models/tsync_data.dart';
import 'mqtt_service.dart';
import 'transport_service.dart';
import 'transport_manager.dart';
import 'ftp_service.dart';

/// Feature flag: Use legacy repeat FFT (firmware-based) vs new repeat FFT (timer-based)
/// - true: Use legacy 0x44 0x04 command (firmware handles repetition)
/// - false: Use timer to repeatedly call Single FFT (0x44 0x01) based on update interval
const bool USE_LEGACY_REPEAT_FFT = false;

/// View mode enum
enum ViewMode { spectrum, iqData, tsync }

/// Application state management
class AppState extends ChangeNotifier {
  final TransportManager _transportManager;

  /// Convenience getter — routes through the currently active transport.
  TransportService get mqttService => _transportManager.active;

  // View mode
  ViewMode _viewMode = ViewMode.spectrum;

  // Measurement settings
  double _centerFreqMhz = 3550.08;// 3000; // MHz (displayed as MHz, converted to Hz for protocol)
  int _rbwIndex = Protocol.defaultRbwIndex;
  bool _maxHold = false;
  int _iqByteSize = 16384; // IQ capture byte size (4 bytes per I/Q pair)
  bool _markerEnabled = true;
  bool _tsyncSaveCsv = true;

  // ── T-Sync ACQ parameters ─────────────────────────────────────────────────
  int _tsyncMode       = 0;       // ACQ_PARAM mode
  int _tsyncSamples    = 2600000; // ACQ_PARAM samples
  int _tsyncHoTime     = 30;      // ACQ_PARAM ho_time (sec)
  int _tsyncDac        = 32768;   // ACQ_PARAM dac (0~65535)
  int _tsyncRunNumber  = 1;       // ACQ_RUN: number of runs
  int _tsyncLoopCount  = 0;       // ACQ_LOOP: count (0 = infinite)
  int _tsyncDelayMs    = 500;     // ACQ_LOOP delay_ms

  // T-Sync ACQ runtime state
  bool _tsyncInitialized = false;
  bool _tsyncRunning     = false; // ACQ_RUN in progress
  bool _tsyncLooping     = false; // ACQ_LOOP in progress
  TsyncStatus?    _tsyncStatus;
  TsyncAcqResult? _tsyncLastResult;
  final List<TsyncIterResult> _tsyncResults = [];
  final Map<int, TsyncFtpStatus> _tsyncFtpStatus = {};
  // ─────────────────────────────────────────────────────────────────────────

  // Measurement state
  bool _isMeasuring = false;

  // FFT length for spectrum measurement
  int _fftLength = Protocol.defaultFftLength;

  // Repeated measurement settings
  int _repeatCount = 10; // Number of repetitions for continuous mode
  int _currentIteration = 0;
  int _totalCount = 0;

  // Data
  SpectrumData? _spectrumData;
  SpectrumData? _maxHoldData;
  IqData? _iqData;

  // Subscriptions
  StreamSubscription? _responseSubscription;
  StreamSubscription? _spectrumSubscription;
  StreamSubscription? _iqSubscription;
  StreamSubscription? _tsyncIterSubscription;
  StreamSubscription? _tsyncStatusSubscription;
  StreamSubscription? _tsyncAcqResultSubscription;

  // Queue for throttling spectrum updates during repeated measurements
  final Queue<Uint8List> _spectrumDataQueue = Queue<Uint8List>();
  Timer? _spectrumUpdateTimer;
  int _chartUpdateIntervalMs = 200; // Default 200ms (5 updates/sec)

  // New repeat FFT (timer-based) variables
  Timer? _repeatTimer;
  int _remainingRepeatCount = 0;

  AppState({required TransportManager transportManager})
      : _transportManager = transportManager {
    _transportManager.addListener(_onTransportChanged);
    _setupSubscriptions();
  }

  // Getters
  ViewMode get viewMode => _viewMode;
  double get centerFreqMhz => _centerFreqMhz;
  int get centerFreqHz => (_centerFreqMhz * 1000000).round();
  int get rbwIndex => _rbwIndex;
  RbwOption get currentRbw => Protocol.rbwOptions[_rbwIndex];
  bool get maxHold => _maxHold;
  int get iqByteSize => _iqByteSize;
  bool get markerEnabled => _markerEnabled;
  bool get tsyncSaveCsv => _tsyncSaveCsv;

  // T-Sync getters
  int  get tsyncMode        => _tsyncMode;
  int  get tsyncSamples     => _tsyncSamples;
  int  get tsyncHoTime      => _tsyncHoTime;
  int  get tsyncDac         => _tsyncDac;
  int  get tsyncRunNumber   => _tsyncRunNumber;
  int  get tsyncLoopCount   => _tsyncLoopCount;
  int  get tsyncDelayMs     => _tsyncDelayMs;
  bool get tsyncInitialized => _tsyncInitialized;
  bool get tsyncRunning     => _tsyncRunning;
  bool get tsyncLooping     => _tsyncLooping;
  TsyncStatus?    get tsyncStatus     => _tsyncStatus;
  TsyncAcqResult? get tsyncLastResult => _tsyncLastResult;
  List<TsyncIterResult>         get tsyncResults   => List.unmodifiable(_tsyncResults);
  Map<int, TsyncFtpStatus>      get tsyncFtpStatus => Map.unmodifiable(_tsyncFtpStatus);

  bool get isMeasuring => _isMeasuring;
  int get fftLength => _fftLength;
  int get repeatCount => _repeatCount;
  int get currentIteration => _currentIteration;
  int get totalCount => _totalCount;
  int get chartUpdateIntervalMs => _chartUpdateIntervalMs;
  int get queuedSpectrumCount => _spectrumDataQueue.length;
  SpectrumData? get spectrumData => _spectrumData;
  SpectrumData? get maxHoldData => _maxHoldData;
  IqData? get iqData => _iqData;

  // Setters
  set viewMode(ViewMode value) {
    _viewMode = value;
    notifyListeners();
  }

  set centerFreqMhz(double value) {
    if (value < 60) value = 60;
    if (value > 6000) value = 6000;
    _centerFreqMhz = value;
    notifyListeners();
  }

  set rbwIndex(int value) {
    if (value >= 0 && value < Protocol.rbwOptions.length) {
      _rbwIndex = value;
      notifyListeners();
    }
  }

  set maxHold(bool value) {
    _maxHold = value;
    if (!value) {
      _maxHoldData = null;
    }
    notifyListeners();
  }

  set tsyncSaveCsv(bool value) {
    _tsyncSaveCsv = value;
    notifyListeners();
  }

  set tsyncMode(int v)      { _tsyncMode = v;      notifyListeners(); }
  set tsyncSamples(int v)   { _tsyncSamples = v;   notifyListeners(); }
  set tsyncHoTime(int v)    { _tsyncHoTime = v;    notifyListeners(); }
  set tsyncDac(int v)       { _tsyncDac = v;       notifyListeners(); }
  set tsyncRunNumber(int v) { _tsyncRunNumber = v; notifyListeners(); }
  set tsyncLoopCount(int v) { _tsyncLoopCount = v; notifyListeners(); }
  set tsyncDelayMs(int v)   { _tsyncDelayMs = v;   notifyListeners(); }

  set iqByteSize(int value) {
    if (value >= 4 && value <= Protocol.maxIqSamples * 4) {
      _iqByteSize = value;
      notifyListeners();
    }
  }

  set markerEnabled(bool value) {
    _markerEnabled = value;
    notifyListeners();
  }

  set fftLength(int value) {
    if (value > 0 && value <= Protocol.maxFftLength) {
      _fftLength = value;
      // Reset max hold data when FFT length changes
      _maxHoldData = null;
      notifyListeners();
    }
  }

  set repeatCount(int value) {
    if (value > 0 && value <= 1000) {
      _repeatCount = value;
      notifyListeners();
    }
  }

  set chartUpdateIntervalMs(int value) {
    if (value >= 100 && value <= 1000) {
      _chartUpdateIntervalMs = value;
      // Restart timer with new interval if currently measuring
      if (_isMeasuring && _totalCount > 0) {
        _stopUpdateTimer();
        _startUpdateTimer();
      }
      notifyListeners();
    }
  }

  void _cancelSubscriptions() {
    _responseSubscription?.cancel();
    _spectrumSubscription?.cancel();
    _iqSubscription?.cancel();
    _tsyncIterSubscription?.cancel();
    _tsyncStatusSubscription?.cancel();
    _tsyncAcqResultSubscription?.cancel();
    _responseSubscription = null;
    _spectrumSubscription = null;
    _iqSubscription = null;
    _tsyncIterSubscription = null;
    _tsyncStatusSubscription = null;
    _tsyncAcqResultSubscription = null;
  }

  /// Re-subscribe when the active transport changes.
  void _onTransportChanged() {
    _cancelSubscriptions();
    _setupSubscriptions();
    // Reset measurement state when switching transports.
    _isMeasuring = false;
    notifyListeners();
  }

  void _setupSubscriptions() {
    _responseSubscription = mqttService.responseStream.listen(_handleResponse);
    _spectrumSubscription = mqttService.spectrumDataStream.listen(_queueSpectrumData);
    _iqSubscription = mqttService.iqDataStream.listen(_handleIqData);
    _tsyncIterSubscription = mqttService.tsyncIterStream.listen(_handleTsyncIter);
    _tsyncStatusSubscription = mqttService.tsyncStatusStream.listen(_handleTsyncStatus);
    _tsyncAcqResultSubscription = mqttService.tsyncAcqResultStream.listen(_handleTsyncAcqResult);
  }

  void _startUpdateTimer() {
    _spectrumUpdateTimer?.cancel();
    _spectrumUpdateTimer = Timer.periodic(
      Duration(milliseconds: _chartUpdateIntervalMs),
      (_) => _processQueuedSpectrumData(),
    );
  }

  void _stopUpdateTimer() {
    _spectrumUpdateTimer?.cancel();
    _spectrumUpdateTimer = null;
  }

  void _startRepeatTimer() {
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(
      Duration(milliseconds: _chartUpdateIntervalMs),
      (_) => _executeNextRepeat(),
    );
    // Execute first one immediately
    _executeNextRepeat();
  }

  void _stopRepeatTimer() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _executeNextRepeat() {
    debugPrint('_remainingRepeatCount=$_remainingRepeatCount, initialized=${mqttService.isInitialized}');

    if (_remainingRepeatCount <= 0 || !mqttService.isInitialized) {
      // Stop repeating
      _stopRepeatTimer();
      _isMeasuring = false;
      _currentIteration = 0;
      _totalCount = 0;
      _remainingRepeatCount = 0;
      notifyListeners();
      return;
    }

    // Send Single FFT command
    mqttService.sendSpectrumCommand(
      freqHz: centerFreqHz,
      rbwHz: currentRbw.valueHz,
      fftLen: _fftLength,
    );

    // Update iteration count
    _currentIteration = _totalCount - _remainingRepeatCount + 1;
    _remainingRepeatCount--;
    notifyListeners();
  }

  void _handleResponse(MqttResponse response) {
    debugPrint('Response: type=${response.type}, status=${response.statusMessage}');

    if (USE_LEGACY_REPEAT_FFT) {
      // Legacy mode: Handle firmware-based repeated spectrum responses
      if (response.type == Protocol.typeRepeatedSpectrum &&
          response.currentIteration != null &&
          response.totalCount != null) {
        _currentIteration = response.currentIteration!;
        _totalCount = response.totalCount!;

        // Check if this is the last iteration
        if (_currentIteration >= _totalCount) {
          // Process any remaining queued data
          while (_spectrumDataQueue.isNotEmpty) {
            _processQueuedSpectrumData();
          }
          _stopUpdateTimer();
          _isMeasuring = false;
          _currentIteration = 0;
          _totalCount = 0;
        }

        notifyListeners();
      } else if (!response.isOk) {
        _stopUpdateTimer();
        _spectrumDataQueue.clear();
        _isMeasuring = false;
        _currentIteration = 0;
        _totalCount = 0;
        notifyListeners();
      }
    } else {
      // New mode: Single FFT responses during repeat operation
      // No special handling needed - each response is independent
      if (!response.isOk) {
        _stopRepeatTimer();
        _spectrumDataQueue.clear();
        _isMeasuring = false;
        _currentIteration = 0;
        _totalCount = 0;
        _remainingRepeatCount = 0;
        notifyListeners();
      }
    }
  }

  /// Queue incoming spectrum data (called from stream)
  void _queueSpectrumData(Uint8List data) {
    final expectedSize = _fftLength * 4;
    if (data.length != expectedSize) {
      debugPrint('Invalid spectrum data size: ${data.length}, expected: $expectedSize');
      return;
    }

    if (USE_LEGACY_REPEAT_FFT) {
      // Legacy mode: Queue data for throttled updates
      if (_totalCount > 0) {
        _spectrumDataQueue.add(data);
        // Limit queue size to prevent memory issues (keep only last 50 items)
        while (_spectrumDataQueue.length > 50) {
          _spectrumDataQueue.removeFirst();
        }
      } else {
        // For single shot, process immediately
        _processSpectrumData(data);
      }
    } else {
      // New mode: Always process immediately (timer controls repetition rate)
      _processSpectrumData(data);
    }
  }

  /// Process queued spectrum data (called by timer during repeated measurements)
  void _processQueuedSpectrumData() {
    if (_spectrumDataQueue.isEmpty) return;

    // Process the oldest queued data
    final data = _spectrumDataQueue.removeFirst();
    _processSpectrumData(data);
  }

  /// Process spectrum data and update chart
  void _processSpectrumData(Uint8List data) {
    _spectrumData = SpectrumData.fromBinary(
      binaryData: data,
      centerFreqKhz: (_centerFreqMhz * 1000).round(),
      rbwIndex: _rbwIndex,
    );

    // Update max hold data
    if (_maxHold) {
      // Reset max hold if FFT size changed
      if (_maxHoldData != null &&
          _maxHoldData!.powerDbm.length != _spectrumData!.powerDbm.length) {
        _maxHoldData = null;
      }

      if (_maxHoldData != null) {
        // Update max hold with element-wise maximum
        final newPower = <double>[];
        final pointCount = _spectrumData!.powerDbm.length;
        for (int i = 0; i < pointCount; i++) {
          newPower.add(
            _spectrumData!.powerDbm[i] > _maxHoldData!.powerDbm[i]
                ? _spectrumData!.powerDbm[i]
                : _maxHoldData!.powerDbm[i],
          );
        }
        _maxHoldData = SpectrumData(
          centerFreqKhz: (_centerFreqMhz * 1000).round(),
          rbwIndex: _rbwIndex,
          powerDbm: newPower,
          fftPoints: _fftLength,
        );
      } else {
        // Initialize max hold with current data
        _maxHoldData = _spectrumData;
      }
    }

    // Only stop measuring if not in repeated mode (_totalCount == 0)
    if (_totalCount == 0) {
      _isMeasuring = false;
    }
    notifyListeners();
  }

  void _handleIqData(Uint8List data) {
    final expectedSize = _iqByteSize;
    debugPrint('[IQ] Received data.length: ${data.length}, expectedSize: $expectedSize');
    if (data.length != expectedSize) {
      debugPrint('[IQ] Invalid IQ data size: ${data.length}, expected: $expectedSize');
      return;
    }

    _iqData = IqData.fromBinary(
      binaryData: data,
      centerFreqKhz: (_centerFreqMhz * 1000).round(),
      sampleCount: _iqByteSize,  // byte size (IqData.fromBinary calculates actual samples from length)
    );

    debugPrint('[IQ] Parsed sampleCount: ${_iqData!.sampleCount} (bytes/${data.length} / 4 = ${data.length ~/ 4})');

    _isMeasuring = false;
    notifyListeners();
  }

  /// Initialize AD9361 61.44MHz mode
  void initialize() {
    mqttService.sendInitCommand();
  }

  /// Request single FFT spectrum measurement
  void requestSpectrum() {
    if (!mqttService.isInitialized) {
      debugPrint('Not initialized');
      return;
    }

    _isMeasuring = true;
    _currentIteration = 0;
    _totalCount = 0;
    notifyListeners();

    mqttService.sendSpectrumCommand(
      freqHz: centerFreqHz,
      rbwHz: currentRbw.valueHz,
      fftLen: _fftLength,
    );
  }

  /// Request repeated FFT spectrum measurement
  void requestRepeatedSpectrum() {
    if (!mqttService.isInitialized) {
      debugPrint('Not initialized');
      return;
    }

    if (USE_LEGACY_REPEAT_FFT) {
      // Legacy mode: Use firmware-based repeated spectrum (0x44 0x04)
      _isMeasuring = true;
      _currentIteration = 0;
      _totalCount = _repeatCount;
      _spectrumDataQueue.clear();
      _startUpdateTimer();
      notifyListeners();

      mqttService.sendRepeatedSpectrumCommand(
        freqHz: centerFreqHz,
        rbwHz: currentRbw.valueHz,
        fftLen: _fftLength,
        count: _repeatCount,
      );
    } else {
      // New mode: Use timer to repeatedly call Single FFT
      _isMeasuring = true;
      _currentIteration = 0;
      _totalCount = _repeatCount;
      _remainingRepeatCount = _repeatCount;
      _spectrumDataQueue.clear();
      notifyListeners();

      // Start the repeat timer
      _startRepeatTimer();
    }
  }

  /// Request single IQ capture
  void requestIqCapture() {
    if (!mqttService.isInitialized) {
      debugPrint('Not initialized');
      return;
    }

    _isMeasuring = true;
    notifyListeners();

    mqttService.sendIqCaptureCommand(
      freqHz: centerFreqHz,
      rbwHz: currentRbw.valueHz,
      iqByteSize: _iqByteSize,
    );
  }

  // ── T-Sync ACQ handlers ───────────────────────────────────────────────────

  void _handleTsyncIter(TsyncIterResult result) {
    _tsyncResults.add(result);
    // Keep last 500 rows
    if (_tsyncResults.length > 500) _tsyncResults.removeAt(0);

    // Detect file_saved and trigger FTP download
    if (result.fileSaved == 1) {
      final counter = result.fileCounter;
      if (!_tsyncFtpStatus.containsKey(counter)) {
        _tsyncFtpStatus[counter] = TsyncFtpStatus(fileCounter: counter);
        _triggerFtpDownload(counter);
      }
    }

    // ACQ_RUN: if all iterations done, mark not running
    if (_tsyncRunning && result.total > 0 && result.iter >= result.total) {
      _tsyncRunning = false;
    }

    notifyListeners();
  }

  void _handleTsyncStatus(TsyncStatus status) {
    _tsyncStatus = status;
    notifyListeners();
  }

  void _handleTsyncAcqResult(TsyncAcqResult result) {
    _tsyncLastResult = result;
    notifyListeners();
  }

  void _triggerFtpDownload(int fileCounter) async {
    final ftpSvc = FtpService(host: mqttService.brokerIp);
    try {
      final result = await ftpSvc.downloadIqFiles(fileCounter);

      final status = _tsyncFtpStatus[fileCounter]!;
      status.iDownloaded = true;
      status.qDownloaded = true;

      if (_tsyncSaveCsv) {
        final dir = await getApplicationDocumentsDirectory();
        final counterStr = fileCounter.toString().padLeft(4, '0');
        final csvPath = '${dir.path}/tsync_IQ_$counterStr.csv';
        await saveIqCsv(
          filePath: csvPath,
          fileCounter: fileCounter,
          iData: result.iData,
          qData: result.qData,
        );
        status.csvSaved = true;
        debugPrint('[tsync] CSV saved: $csvPath');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[tsync] FTP download failed for #$fileCounter: $e');
    }
  }

  // ── T-Sync ACQ actions ────────────────────────────────────────────────────

  /// Send ACQ_INIT
  void tsyncInit() {
    mqttService.sendAcqInit();
    _tsyncInitialized = true;
    notifyListeners();
  }

  /// Send ACQ_PARAM with current parameter values
  void tsyncApplyParam() {
    mqttService.sendAcqParam(
      mode:    _tsyncMode,
      samples: _tsyncSamples,
      hoTime:  _tsyncHoTime,
      dac:     _tsyncDac,
    );
  }

  /// Send ACQ_RUN (0x44 0x62 <runNumber>)
  void tsyncRun() {
    if (!mqttService.isConnected) return;
    _tsyncRunning = true;
    notifyListeners();
    mqttService.sendAcqRun(_tsyncRunNumber);
  }

  /// Send ACQ_LOOP (0x44 0x65 <loopCount> <delayMs>)
  void tsyncLoop() {
    if (!mqttService.isConnected) return;
    _tsyncLooping = true;
    notifyListeners();
    mqttService.sendAcqLoop(count: _tsyncLoopCount, delayMs: _tsyncDelayMs);
  }

  /// Send ACQ_STOP (0x44 0x66) — stops loop
  void tsyncStop() {
    mqttService.sendAcqStop();
    _tsyncLooping = false;
    notifyListeners();
  }

  /// Send ACQ_STATUS query
  void tsyncQueryStatus() => mqttService.sendAcqStatus();

  /// Export current tsync result table to CSV.
  /// Saves to <executable_dir>/csv/tsync_YYYYMMDDHHMMSS.csv
  /// Returns the saved file path, or null on error.
  Future<String?> tsyncExportCsv() async {
    if (_tsyncResults.isEmpty) return null;
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final csvDir = Directory(p.join(exeDir, 'csv'));
      if (!csvDir.existsSync()) csvDir.createSync(recursive: true);

      final now = DateTime.now();
      final timestamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';

      final filePath = p.join(csvDir.path, 'tsync_$timestamp.csv');

      final sb = StringBuffer();
      sb.writeln('Timestamp,Iter,State,Lock,SSB Lock,PCI,Beam,CRC,Corr,DAC');
      for (final r in _tsyncResults) {
        final ts = r.timestamp;
        final tsStr =
            '${ts.year.toString().padLeft(4, '0')}-'
            '${ts.month.toString().padLeft(2, '0')}-'
            '${ts.day.toString().padLeft(2, '0')} '
            '${ts.hour.toString().padLeft(2, '0')}:'
            '${ts.minute.toString().padLeft(2, '0')}:'
            '${ts.second.toString().padLeft(2, '0')}.'
            '${ts.millisecond.toString().padLeft(3, '0')}';
        sb.writeln(
          '"$tsStr",${r.iter},${r.stateName},${r.lockName},${r.ssbLockName},'
          '${r.pci},${r.beam},${r.crcOk ? 'OK' : 'FAIL'},${r.corr},${r.curDac}',
        );
      }

      await File(filePath).writeAsString(sb.toString());
      debugPrint('[tsync] CSV exported: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[tsync] CSV export failed: $e');
      return null;
    }
  }

  /// Clear result history
  void tsyncClearResults() {
    _tsyncResults.clear();
    _tsyncFtpStatus.clear();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Clear max hold data
  void clearMaxHold() {
    _maxHoldData = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _transportManager.removeListener(_onTransportChanged);
    _cancelSubscriptions();
    _stopUpdateTimer();
    _stopRepeatTimer();
    _spectrumDataQueue.clear();
    super.dispose();
  }
}
