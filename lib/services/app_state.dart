import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../constants/protocol.dart';
import '../models/spectrum_data.dart';
import '../models/iq_data.dart';
import 'mqtt_service.dart';

/// View mode enum
enum ViewMode { spectrum, iqData }

/// Application state management
class AppState extends ChangeNotifier {
  final MqttService mqttService;

  // View mode
  ViewMode _viewMode = ViewMode.spectrum;

  // Measurement settings
  int _centerFreqMhz = 3000; // MHz (displayed as MHz, converted to Hz for protocol)
  int _rbwIndex = Protocol.defaultRbwIndex;
  bool _maxHold = false;
  int _iqByteSize = 16384; // IQ capture byte size (4 bytes per I/Q pair)
  bool _markerEnabled = true;

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

  // Queue for throttling spectrum updates during repeated measurements
  final Queue<Uint8List> _spectrumDataQueue = Queue<Uint8List>();
  Timer? _spectrumUpdateTimer;
  int _chartUpdateIntervalMs = 200; // Default 200ms (5 updates/sec)

  AppState({required this.mqttService}) {
    _setupSubscriptions();
  }

  // Getters
  ViewMode get viewMode => _viewMode;
  int get centerFreqMhz => _centerFreqMhz;
  int get centerFreqHz => _centerFreqMhz * 1000000;
  int get rbwIndex => _rbwIndex;
  RbwOption get currentRbw => Protocol.rbwOptions[_rbwIndex];
  bool get maxHold => _maxHold;
  int get iqByteSize => _iqByteSize;
  bool get markerEnabled => _markerEnabled;
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

  set centerFreqMhz(int value) {
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
    if (value > 0 && value <= 10000) {
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

  void _setupSubscriptions() {
    _responseSubscription = mqttService.responseStream.listen(_handleResponse);
    _spectrumSubscription = mqttService.spectrumDataStream.listen(_queueSpectrumData);
    _iqSubscription = mqttService.iqDataStream.listen(_handleIqData);
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

  void _handleResponse(MqttResponse response) {
    debugPrint('Response: type=${response.type}, status=${response.statusMessage}');

    // Update iteration info for repeated spectrum
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
  }

  /// Queue incoming spectrum data (called from stream)
  void _queueSpectrumData(Uint8List data) {
    final expectedSize = _fftLength * 4;
    if (data.length != expectedSize) {
      debugPrint('Invalid spectrum data size: ${data.length}, expected: $expectedSize');
      return;
    }

    // For repeated measurements, queue the data for throttled updates
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
      centerFreqKhz: _centerFreqMhz * 1000,
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
          centerFreqKhz: _centerFreqMhz * 1000,
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
      centerFreqKhz: _centerFreqMhz * 1000,
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

  /// Clear max hold data
  void clearMaxHold() {
    _maxHoldData = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _responseSubscription?.cancel();
    _spectrumSubscription?.cancel();
    _iqSubscription?.cancel();
    _stopUpdateTimer();
    _spectrumDataQueue.clear();
    super.dispose();
  }
}
