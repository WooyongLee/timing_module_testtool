import 'dart:math' as math;
import 'dart:typed_data';

/// IQ capture data
class IqData {
  final int centerFreqKhz;
  final List<int> iChannel;
  final List<int> qChannel;
  final DateTime timestamp;

  IqData({
    required this.centerFreqKhz,
    required this.iChannel,
    required this.qChannel,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  int get sampleCount => iChannel.length;

  /// Parse binary IQ data (I16, Q16 pairs, Little Endian)
  /// Each sample = 4 bytes (I: 2 bytes + Q: 2 bytes)
  factory IqData.fromBinary({
    required Uint8List binaryData,
    required int centerFreqKhz,
    required int sampleCount, // This is byte length from firmware
  }) {
    final byteData = ByteData.sublistView(binaryData);
    final iChannel = <int>[];
    final qChannel = <int>[];

    // Calculate actual sample count from binary data length
    // Each I/Q pair = 4 bytes (I: int16 + Q: int16)
    final actualSampleCount = binaryData.length ~/ 4;

    for (int i = 0; i < actualSampleCount; i++) {
      iChannel.add(byteData.getInt16(i * 4, Endian.little));
      qChannel.add(byteData.getInt16(i * 4 + 2, Endian.little));
    }

    return IqData(
      centerFreqKhz: centerFreqKhz,
      iChannel: iChannel,
      qChannel: qChannel,
    );
  }

  /// Get normalized I values (for display)
  List<double> get iNormalized {
    final maxVal = 32768.0;
    return iChannel.map((v) => v / maxVal).toList();
  }

  /// Get normalized Q values (for display)
  List<double> get qNormalized {
    final maxVal = 32768.0;
    return qChannel.map((v) => v / maxVal).toList();
  }

  /// Calculate magnitude for each sample
  List<double> get magnitude {
    return List.generate(sampleCount, (i) {
      final iVal = iChannel[i].toDouble();
      final qVal = qChannel[i].toDouble();
      return math.sqrt(iVal * iVal + qVal * qVal);
    });
  }

  /// Export to CSV format
  String toCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Sample,I,Q');

    for (int i = 0; i < sampleCount; i++) {
      buffer.writeln('$i,${iChannel[i]},${qChannel[i]}');
    }

    return buffer.toString();
  }
}
