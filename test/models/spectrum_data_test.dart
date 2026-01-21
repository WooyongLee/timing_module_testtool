import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:timing_module_testtool/models/spectrum_data.dart';
import 'package:timing_module_testtool/constants/protocol.dart';
import '../helpers/test_data_generator.dart';

void main() {
  group('SpectrumData', () {
    group('fromBinary', () {
      test('should parse binary data correctly', () {
        // Arrange
        const centerFreqKhz = 3000000; // 3 GHz
        const rbwIndex = 2;
        final binaryData = TestDataGenerator.generateSpectrumData(
          peakBin: 4096,
          peakDbm: -20.0,
          noiseFloorDbm: -80.0,
        );

        // Act
        final spectrum = SpectrumData.fromBinary(
          binaryData: binaryData,
          centerFreqKhz: centerFreqKhz,
          rbwIndex: rbwIndex,
        );

        // Assert
        expect(spectrum.powerDbm.length, equals(Protocol.spectrumPoints));
        expect(spectrum.centerFreqKhz, equals(centerFreqKhz));
        expect(spectrum.rbwIndex, equals(rbwIndex));
      });

      test('should parse known values correctly', () {
        // Arrange - create data with known values
        final byteData = ByteData(Protocol.spectrumPoints * 4);

        // Set specific values: -50.00 dBm = -5000
        byteData.setInt32(0, -5000, Endian.little);
        byteData.setInt32(4, -3000, Endian.little); // -30.00 dBm
        byteData.setInt32(8, -7500, Endian.little); // -75.00 dBm

        // Fill rest with zeros
        for (int i = 3; i < Protocol.spectrumPoints; i++) {
          byteData.setInt32(i * 4, 0, Endian.little);
        }

        final binaryData = byteData.buffer.asUint8List();

        // Act
        final spectrum = SpectrumData.fromBinary(
          binaryData: binaryData,
          centerFreqKhz: 2000000,
          rbwIndex: 0,
        );

        // Assert
        expect(spectrum.powerDbm[0], closeTo(-50.0, 0.01));
        expect(spectrum.powerDbm[1], closeTo(-30.0, 0.01));
        expect(spectrum.powerDbm[2], closeTo(-75.0, 0.01));
      });

      test('should handle negative and positive values', () {
        // Arrange
        final byteData = ByteData(Protocol.spectrumPoints * 4);
        byteData.setInt32(0, -8000, Endian.little); // -80 dBm
        byteData.setInt32(4, 500, Endian.little); // +5 dBm (rare but possible)

        for (int i = 2; i < Protocol.spectrumPoints; i++) {
          byteData.setInt32(i * 4, -6000, Endian.little);
        }

        // Act
        final spectrum = SpectrumData.fromBinary(
          binaryData: byteData.buffer.asUint8List(),
          centerFreqKhz: 1000000,
          rbwIndex: 1,
        );

        // Assert
        expect(spectrum.powerDbm[0], closeTo(-80.0, 0.01));
        expect(spectrum.powerDbm[1], closeTo(5.0, 0.01));
      });
    });

    group('getFrequencyAxisMhz', () {
      test('should generate correct frequency axis', () {
        // Arrange
        final spectrum = SpectrumData(
          centerFreqKhz: 3000000, // 3 GHz
          rbwIndex: 2,
          powerDbm: List.filled(Protocol.spectrumPoints, -60.0),
        );

        // Act
        final freqAxis = spectrum.getFrequencyAxisMhz();

        // Assert
        expect(freqAxis.length, equals(Protocol.spectrumPoints));
        // Center should be at 3000 MHz
        expect(freqAxis[Protocol.spectrumPoints ~/ 2], closeTo(3000.0, 0.1));
        // Span is 61.44 MHz
        expect(freqAxis.last - freqAxis.first, closeTo(61.44, 0.1));
      });
    });

    group('frequency range properties', () {
      test('should calculate start and stop frequencies correctly', () {
        // Arrange
        final spectrum = SpectrumData(
          centerFreqKhz: 2000000, // 2 GHz
          rbwIndex: 0,
          powerDbm: List.filled(Protocol.spectrumPoints, -60.0),
        );

        // Assert
        expect(spectrum.spanMhz, closeTo(61.44, 0.01));
        expect(spectrum.startFreqMhz, closeTo(2000.0 - 30.72, 0.01));
        expect(spectrum.stopFreqMhz, closeTo(2000.0 + 30.72, 0.01));
      });
    });

    group('findPeak', () {
      test('should find peak correctly', () {
        // Arrange
        final powerDbm = List.filled(Protocol.spectrumPoints, -80.0);
        powerDbm[1000] = -20.0; // Peak at bin 1000

        final spectrum = SpectrumData(
          centerFreqKhz: 3000000,
          rbwIndex: 2,
          powerDbm: powerDbm,
        );

        // Act
        final peak = spectrum.findPeak();

        // Assert
        expect(peak.index, equals(1000));
        expect(peak.power, closeTo(-20.0, 0.01));
      });

      test('should find peak in generated data', () {
        // Arrange
        final binaryData = TestDataGenerator.generateSpectrumData(
          peakBin: 5000,
          peakDbm: -15.0,
          noiseFloorDbm: -85.0,
        );

        final spectrum = SpectrumData.fromBinary(
          binaryData: binaryData,
          centerFreqKhz: 2500000,
          rbwIndex: 1,
        );

        // Act
        final peak = spectrum.findPeak();

        // Assert
        expect(peak.index, equals(5000));
        expect(peak.power, closeTo(-15.0, 1.0)); // Allow some tolerance
      });
    });

    group('toCsv', () {
      test('should generate valid CSV format', () {
        // Arrange
        final spectrum = SpectrumData(
          centerFreqKhz: 1000000,
          rbwIndex: 0,
          powerDbm: List.generate(Protocol.spectrumPoints, (i) => -60.0 + i * 0.001),
        );

        // Act
        final csv = spectrum.toCsv();
        final lines = csv.split('\n');

        // Assert
        expect(lines[0], equals('Frequency (MHz),Power (dBm)'));
        expect(lines.length, greaterThan(Protocol.spectrumPoints)); // Header + data
      });
    });
  });
}
