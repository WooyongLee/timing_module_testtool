import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:timing_module_testtool/models/iq_data.dart';
import '../helpers/test_data_generator.dart';

void main() {
  group('IqData', () {
    group('fromBinary', () {
      test('should parse binary data correctly', () {
        // Arrange
        const sampleCount = 4096;
        const centerFreqKhz = 2000000;
        final binaryData = TestDataGenerator.generateIqData(
          sampleCount: sampleCount,
          amplitude: 10000,
        );

        // Act
        final iqData = IqData.fromBinary(
          binaryData: binaryData,
          centerFreqKhz: centerFreqKhz,
          sampleCount: sampleCount,
        );

        // Assert
        expect(iqData.iChannel.length, equals(sampleCount));
        expect(iqData.qChannel.length, equals(sampleCount));
        expect(iqData.sampleCount, equals(sampleCount));
        expect(iqData.centerFreqKhz, equals(centerFreqKhz));
      });

      test('should parse known values correctly', () {
        // Arrange
        const sampleCount = 4;
        final byteData = ByteData(sampleCount * 4);

        // Sample 0: I=1000, Q=2000
        byteData.setInt16(0, 1000, Endian.little);
        byteData.setInt16(2, 2000, Endian.little);

        // Sample 1: I=-500, Q=3000
        byteData.setInt16(4, -500, Endian.little);
        byteData.setInt16(6, 3000, Endian.little);

        // Sample 2: I=32767, Q=-32768 (max/min)
        byteData.setInt16(8, 32767, Endian.little);
        byteData.setInt16(10, -32768, Endian.little);

        // Sample 3: I=0, Q=0
        byteData.setInt16(12, 0, Endian.little);
        byteData.setInt16(14, 0, Endian.little);

        // Act
        final iqData = IqData.fromBinary(
          binaryData: byteData.buffer.asUint8List(),
          centerFreqKhz: 1000000,
          sampleCount: sampleCount,
        );

        // Assert
        expect(iqData.iChannel[0], equals(1000));
        expect(iqData.qChannel[0], equals(2000));
        expect(iqData.iChannel[1], equals(-500));
        expect(iqData.qChannel[1], equals(3000));
        expect(iqData.iChannel[2], equals(32767));
        expect(iqData.qChannel[2], equals(-32768));
        expect(iqData.iChannel[3], equals(0));
        expect(iqData.qChannel[3], equals(0));
      });

      test('should handle various sample counts', () {
        for (final count in [1024, 2048, 4096, 8192, 16384]) {
          // Arrange
          final binaryData = TestDataGenerator.generateIqData(sampleCount: count);

          // Act
          final iqData = IqData.fromBinary(
            binaryData: binaryData,
            centerFreqKhz: 3000000,
            sampleCount: count,
          );

          // Assert
          expect(iqData.sampleCount, equals(count));
          expect(iqData.iChannel.length, equals(count));
          expect(iqData.qChannel.length, equals(count));
        }
      });
    });

    group('normalized values', () {
      test('should normalize I values correctly', () {
        // Arrange
        final iqData = IqData(
          centerFreqKhz: 1000000,
          iChannel: [32768, -32768, 0, 16384],
          qChannel: [0, 0, 0, 0],
        );

        // Act
        final iNorm = iqData.iNormalized;

        // Assert
        expect(iNorm[0], closeTo(1.0, 0.001));
        expect(iNorm[1], closeTo(-1.0, 0.001));
        expect(iNorm[2], closeTo(0.0, 0.001));
        expect(iNorm[3], closeTo(0.5, 0.001));
      });

      test('should normalize Q values correctly', () {
        // Arrange
        final iqData = IqData(
          centerFreqKhz: 1000000,
          iChannel: [0, 0, 0, 0],
          qChannel: [32768, -32768, 0, -16384],
        );

        // Act
        final qNorm = iqData.qNormalized;

        // Assert
        expect(qNorm[0], closeTo(1.0, 0.001));
        expect(qNorm[1], closeTo(-1.0, 0.001));
        expect(qNorm[2], closeTo(0.0, 0.001));
        expect(qNorm[3], closeTo(-0.5, 0.001));
      });
    });

    group('magnitude', () {
      test('should calculate magnitude correctly', () {
        // Arrange
        final iqData = IqData(
          centerFreqKhz: 1000000,
          iChannel: [3, 0, 5, 8],
          qChannel: [4, 5, 12, 15],
        );

        // Act
        final mag = iqData.magnitude;

        // Assert
        expect(mag[0], closeTo(5.0, 0.001)); // sqrt(9 + 16) = 5
        expect(mag[1], closeTo(5.0, 0.001)); // sqrt(0 + 25) = 5
        expect(mag[2], closeTo(13.0, 0.001)); // sqrt(25 + 144) = 13
        expect(mag[3], closeTo(17.0, 0.001)); // sqrt(64 + 225) = 17
      });

      test('should calculate magnitude for generated sinusoid', () {
        // Arrange - a pure sinusoid should have constant magnitude
        final binaryData = TestDataGenerator.generateIqData(
          sampleCount: 100,
          amplitude: 10000,
          noiseLevel: 0, // No noise for clean test
        );

        final iqData = IqData.fromBinary(
          binaryData: binaryData,
          centerFreqKhz: 2000000,
          sampleCount: 100,
        );

        // Act
        final mag = iqData.magnitude;

        // Assert - all magnitudes should be close to the amplitude
        for (final m in mag) {
          expect(m, closeTo(10000.0, 100.0)); // Allow some tolerance
        }
      });
    });

    group('toCsv', () {
      test('should generate valid CSV format', () {
        // Arrange
        final iqData = IqData(
          centerFreqKhz: 1000000,
          iChannel: [100, 200, 300],
          qChannel: [400, 500, 600],
        );

        // Act
        final csv = iqData.toCsv();
        final lines = csv.split('\n');

        // Assert
        expect(lines[0], equals('Sample,I,Q'));
        expect(lines[1], equals('0,100,400'));
        expect(lines[2], equals('1,200,500'));
        expect(lines[3], equals('2,300,600'));
      });
    });

    group('timestamp', () {
      test('should set timestamp automatically', () {
        // Arrange & Act
        final beforeCreate = DateTime.now();
        final iqData = IqData(
          centerFreqKhz: 1000000,
          iChannel: [0],
          qChannel: [0],
        );
        final afterCreate = DateTime.now();

        // Assert
        expect(iqData.timestamp.isAfter(beforeCreate.subtract(const Duration(seconds: 1))), isTrue);
        expect(iqData.timestamp.isBefore(afterCreate.add(const Duration(seconds: 1))), isTrue);
      });

      test('should allow custom timestamp', () {
        // Arrange
        final customTime = DateTime(2024, 1, 15, 10, 30, 0);

        // Act
        final iqData = IqData(
          centerFreqKhz: 1000000,
          iChannel: [0],
          qChannel: [0],
          timestamp: customTime,
        );

        // Assert
        expect(iqData.timestamp, equals(customTime));
      });
    });
  });
}
