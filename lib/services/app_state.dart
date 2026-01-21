import 'dart:async';
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
  int _iqSampleCount = 4096;
  bool _markerEnabled = true;

  // Measurement state
  bool _isMeasuring = false;

  // FFT length for spectrum measurement
  int _fftLength = Protocol.defaultFftLength;

  // Data
  SpectrumData? _spectrumData;
  SpectrumData? _maxHoldData;
  IqData? _iqData;

  // Subscriptions
  StreamSubscription? _responseSubscription;
  StreamSubscription? _spectrumSubscription;
  StreamSubscription? _iqSubscription;

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
  int get iqSampleCount => _iqSampleCount;
  bool get markerEnabled => _markerEnabled;
  bool get isMeasuring => _isMeasuring;
  int get fftLength => _fftLength;
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

  set iqSampleCount(int value) {
    if (value >= 1 && value <= Protocol.maxIqSamples) {
      _iqSampleCount = value;
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
      notifyListeners();
    }
  }

  void _setupSubscriptions() {
    _responseSubscription = mqttService.responseStream.listen(_handleResponse);
    _spectrumSubscription = mqttService.spectrumDataStream.listen(_handleSpectrumData);
    _iqSubscription = mqttService.iqDataStream.listen(_handleIqData);
  }

  void _handleResponse(MqttResponse response) {
    debugPrint('Response: type=${response.type}, status=${response.statusMessage}');

    if (!response.isOk) {
      _isMeasuring = false;
      notifyListeners();
    }
  }

  void _handleSpectrumData(Uint8List data) {
    final expectedSize = _fftLength * 4;
    if (data.length != expectedSize) {
      debugPrint('Invalid spectrum data size: ${data.length}, expected: $expectedSize');
      return;
    }

    _spectrumData = SpectrumData.fromBinary(
      binaryData: data,
      centerFreqKhz: _centerFreqMhz * 1000,
      rbwIndex: _rbwIndex,
    );

    // Update max hold data
    if (_maxHold && _maxHoldData != null) {
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
      );
    } else if (_maxHold) {
      _maxHoldData = _spectrumData;
    }

    _isMeasuring = false;
    notifyListeners();
  }

  void _handleIqData(Uint8List data) {
    // edit/4
    final expectedSize = _iqSampleCount; // * 4;
    if (data.length != expectedSize) {
      debugPrint('Invalid IQ data size: ${data.length}, expected: $expectedSize');
      return;
    }

    _iqData = IqData.fromBinary(
      binaryData: data,
      centerFreqKhz: _centerFreqMhz * 1000,
      sampleCount: _iqSampleCount,
    );

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
    notifyListeners();

    mqttService.sendSpectrumCommand(fftLen: _fftLength);
  }

  /// Request single IQ capture
  void requestIqCapture() {
    if (!mqttService.isInitialized) {
      debugPrint('Not initialized');
      return;
    }

    _isMeasuring = true;
    notifyListeners();

    mqttService.sendIqCaptureCommand(sampleCount: _iqSampleCount);
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
    super.dispose();
  }
}
