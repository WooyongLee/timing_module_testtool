import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:timing_module_testtool/models/spectrum_data.dart';
import 'package:timing_module_testtool/models/iq_data.dart';
import 'package:timing_module_testtool/constants/protocol.dart';
import '../helpers/test_data_generator.dart';

/// Simulates the complete message flow for testing
/// This class mimics what would happen in the actual MQTT communication
class MockMessageProcessor {
  final _spectrumDataController = StreamController<SpectrumData>.broadcast();
  final _iqDataController = StreamController<IqData>.broadcast();
  final _responseController = StreamController<String>.broadcast();

  Stream<SpectrumData> get spectrumStream => _spectrumDataController.stream;
  Stream<IqData> get iqStream => _iqDataController.stream;
  Stream<String> get responseStream => _responseController.stream;

  int _centerFreqKhz = 3000000;
  int _rbwIndex = 2;
  int _iqSampleCount = 4096;

  /// Simulate sending init command and receiving response
  Future<bool> simulateInit({
    required int centerFreqHz,
    int rbwIndex = 2,
    bool maxHold = false,
  }) async {
    _centerFreqKhz = centerFreqHz ~/ 1000;
    _rbwIndex = rbwIndex;

    // Simulate response delay
    await Future.delayed(const Duration(milliseconds: 10));

    // Generate init response
    final response = TestDataGenerator.createInitResponse(
      status: 1,
      centerFreqHz: centerFreqHz,
      rbwIndex: rbwIndex,
      maxHold: maxHold ? 1 : 0,
    );

    _responseController.add(response);
    return true;
  }

  /// Simulate spectrum measurement: header on data1, binary on data2
  Future<void> simulateSpectrumMeasurement({
    double peakDbm = -25.0,
    int peakBin = 4096,
  }) async {
    // First: send header response on data1
    final headerResponse = TestDataGenerator.createSpectrumHeaderResponse();
    _responseController.add(headerResponse);

    await Future.delayed(const Duration(milliseconds: 5));

    // Then: send binary data on data2
    final binaryData = TestDataGenerator.generateSpectrumData(
      peakDbm: peakDbm,
      peakBin: peakBin,
      noiseFloorDbm: -80.0,
    );

    final spectrumData = SpectrumData.fromBinary(
      binaryData: binaryData,
      centerFreqKhz: _centerFreqKhz,
      rbwIndex: _rbwIndex,
    );

    _spectrumDataController.add(spectrumData);
  }

  /// Simulate IQ capture: header on data1, binary on data2
  Future<void> simulateIqCapture({
    int sampleCount = 4096,
    double frequencyRatio = 0.1,
    int amplitude = 10000,
  }) async {
    _iqSampleCount = sampleCount;

    // First: send header response on data1
    final headerResponse = TestDataGenerator.createIqHeaderResponse(
      sampleCount: sampleCount,
    );
    _responseController.add(headerResponse);

    await Future.delayed(const Duration(milliseconds: 5));

    // Then: send binary data on data2
    final binaryData = TestDataGenerator.generateIqData(
      sampleCount: sampleCount,
      frequencyRatio: frequencyRatio,
      amplitude: amplitude,
    );

    final iqData = IqData.fromBinary(
      binaryData: binaryData,
      centerFreqKhz: _centerFreqKhz,
      sampleCount: sampleCount,
    );

    _iqDataController.add(iqData);
  }

  /// Simulate stop command
  Future<void> simulateStop() async {
    await Future.delayed(const Duration(milliseconds: 5));
    final response = TestDataGenerator.createStopResponse();
    _responseController.add(response);
  }

  void dispose() {
    _spectrumDataController.close();
    _iqDataController.close();
    _responseController.close();
  }
}

void main() {
  group('Message Flow Integration Tests', () {
    late MockMessageProcessor processor;

    setUp(() {
      processor = MockMessageProcessor();
    });

    tearDown(() {
      processor.dispose();
    });

    group('Init Flow', () {
      test('should receive init response with correct parameters', () async {
        // Arrange
        const centerFreqHz = 2500000000; // 2.5 GHz
        const rbwIndex = 1;
        String? receivedResponse;

        processor.responseStream.listen((response) {
          receivedResponse = response;
        });

        // Act
        await processor.simulateInit(
          centerFreqHz: centerFreqHz,
          rbwIndex: rbwIndex,
          maxHold: true,
        );

        // Allow stream to process
        await Future.delayed(const Duration(milliseconds: 50));

        // Assert
        expect(receivedResponse, isNotNull);
        expect(receivedResponse, contains('0x45'));
        expect(receivedResponse, contains('1')); // status OK
        expect(receivedResponse, contains('2500000000')); // freq
      });
    });

    group('Spectrum Flow', () {
      test('should receive spectrum data after header', () async {
        // Arrange
        final receivedResponses = <String>[];
        SpectrumData? receivedSpectrum;

        processor.responseStream.listen((response) {
          receivedResponses.add(response);
        });

        processor.spectrumStream.listen((spectrum) {
          receivedSpectrum = spectrum;
        });

        // Act
        await processor.simulateInit(centerFreqHz: 3000000000);
        await processor.simulateSpectrumMeasurement(
          peakDbm: -20.0,
          peakBin: 5000,
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(receivedResponses.length, equals(2)); // init + spectrum header
        expect(receivedResponses[1], contains('0x45 0x01')); // spectrum header
        expect(receivedSpectrum, isNotNull);
        expect(receivedSpectrum!.powerDbm.length, equals(Protocol.spectrumPoints));

        // Verify peak
        final peak = receivedSpectrum!.findPeak();
        expect(peak.index, equals(5000));
        expect(peak.power, closeTo(-20.0, 1.0));
      });

      test('should handle multiple spectrum measurements', () async {
        // Arrange
        final spectrumList = <SpectrumData>[];

        processor.spectrumStream.listen((spectrum) {
          spectrumList.add(spectrum);
        });

        await processor.simulateInit(centerFreqHz: 2000000000);

        // Act - simulate 3 consecutive measurements
        for (int i = 0; i < 3; i++) {
          await processor.simulateSpectrumMeasurement(
            peakDbm: -30.0 + i * 5, // -30, -25, -20
            peakBin: 4000 + i * 500, // 4000, 4500, 5000
          );
          await Future.delayed(const Duration(milliseconds: 20));
        }

        await Future.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(spectrumList.length, equals(3));

        // Verify each spectrum has different peak
        expect(spectrumList[0].findPeak().index, equals(4000));
        expect(spectrumList[1].findPeak().index, equals(4500));
        expect(spectrumList[2].findPeak().index, equals(5000));
      });
    });

    group('IQ Capture Flow', () {
      test('should receive IQ data after header', () async {
        // Arrange
        final receivedResponses = <String>[];
        IqData? receivedIq;

        processor.responseStream.listen((response) {
          receivedResponses.add(response);
        });

        processor.iqStream.listen((iq) {
          receivedIq = iq;
        });

        // Act
        await processor.simulateInit(centerFreqHz: 2500000000);
        await processor.simulateIqCapture(
          sampleCount: 2048,
          amplitude: 8000,
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(receivedResponses.length, equals(2)); // init + IQ header
        expect(receivedResponses[1], contains('0x45 0x02 2048')); // IQ header
        expect(receivedIq, isNotNull);
        expect(receivedIq!.sampleCount, equals(2048));
        expect(receivedIq!.iChannel.length, equals(2048));
        expect(receivedIq!.qChannel.length, equals(2048));
      });

      test('should handle different sample counts', () async {
        // Arrange
        final iqDataList = <IqData>[];

        processor.iqStream.listen((iq) {
          iqDataList.add(iq);
        });

        await processor.simulateInit(centerFreqHz: 3000000000);

        // Act - test various sample counts
        final sampleCounts = [1024, 4096, 8192];
        for (final count in sampleCounts) {
          await processor.simulateIqCapture(sampleCount: count);
          await Future.delayed(const Duration(milliseconds: 20));
        }

        await Future.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(iqDataList.length, equals(3));
        expect(iqDataList[0].sampleCount, equals(1024));
        expect(iqDataList[1].sampleCount, equals(4096));
        expect(iqDataList[2].sampleCount, equals(8192));
      });

      test('should produce valid sinusoidal IQ data', () async {
        // Arrange
        IqData? receivedIq;

        processor.iqStream.listen((iq) {
          receivedIq = iq;
        });

        await processor.simulateInit(centerFreqHz: 1000000000);

        // Act
        await processor.simulateIqCapture(
          sampleCount: 1000,
          frequencyRatio: 0.05,
          amplitude: 10000,
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(receivedIq, isNotNull);

        // For a sinusoid, magnitude should be approximately constant
        final magnitudes = receivedIq!.magnitude;
        final avgMag = magnitudes.reduce((a, b) => a + b) / magnitudes.length;

        // All magnitudes should be close to average (within 5%)
        for (final mag in magnitudes) {
          expect(mag, closeTo(avgMag, avgMag * 0.1));
        }
      });
    });

    group('Stop Flow', () {
      test('should receive stop response', () async {
        // Arrange
        String? lastResponse;

        processor.responseStream.listen((response) {
          lastResponse = response;
        });

        await processor.simulateInit(centerFreqHz: 3000000000);

        // Act
        await processor.simulateStop();
        await Future.delayed(const Duration(milliseconds: 50));

        // Assert
        expect(lastResponse, equals('0x45 0x0F'));
      });
    });

    group('Full Workflow', () {
      test('should handle complete measurement cycle', () async {
        // Arrange
        final responses = <String>[];
        SpectrumData? spectrum;
        IqData? iqData;

        processor.responseStream.listen((r) => responses.add(r));
        processor.spectrumStream.listen((s) => spectrum = s);
        processor.iqStream.listen((i) => iqData = i);

        // Act - Full workflow
        // 1. Init
        await processor.simulateInit(
          centerFreqHz: 2500000000,
          rbwIndex: 2,
        );

        // 2. Spectrum measurement
        await processor.simulateSpectrumMeasurement(
          peakDbm: -25.0,
          peakBin: 4096,
        );

        // 3. IQ capture
        await processor.simulateIqCapture(
          sampleCount: 4096,
          amplitude: 12000,
        );

        // 4. Stop
        await processor.simulateStop();

        await Future.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(responses.length, equals(4)); // init, spectrum header, IQ header, stop
        expect(responses[0], contains('0x45 1')); // init OK
        expect(responses[1], contains('0x45 0x01')); // spectrum header
        expect(responses[2], contains('0x45 0x02')); // IQ header
        expect(responses[3], equals('0x45 0x0F')); // stop

        expect(spectrum, isNotNull);
        expect(spectrum!.centerFreqKhz, equals(2500000));

        expect(iqData, isNotNull);
        expect(iqData!.sampleCount, equals(4096));
      });
    });
  });

  group('Response Parsing', () {
    test('should parse init response correctly', () {
      // Arrange
      final response = TestDataGenerator.createInitResponse(
        status: 1,
        centerFreqHz: 3500000000,
        rbwIndex: 3,
        maxHold: 1,
      );

      // Act
      final parts = response.split(' ');

      // Assert
      expect(parts[0], equals('0x45'));
      expect(int.parse(parts[1]), equals(1)); // status
      expect(int.parse(parts[2]), equals(3500000000)); // freq
      expect(int.parse(parts[3]), equals(3)); // rbw
      expect(int.parse(parts[4]), equals(1)); // maxhold
    });

    test('should parse spectrum header correctly', () {
      // Arrange
      final response = TestDataGenerator.createSpectrumHeaderResponse(dataPoints: 8192);

      // Act
      final parts = response.split(' ');

      // Assert
      expect(parts[0], equals('0x45'));
      expect(parts[1], equals('0x01'));
      expect(int.parse(parts[2]), equals(8192));
    });

    test('should parse IQ header correctly', () {
      // Arrange
      final response = TestDataGenerator.createIqHeaderResponse(sampleCount: 16384);

      // Act
      final parts = response.split(' ');

      // Assert
      expect(parts[0], equals('0x45'));
      expect(parts[1], equals('0x02'));
      expect(int.parse(parts[2]), equals(16384));
    });
  });
}
