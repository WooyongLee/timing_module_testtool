import 'dart:typed_data';
import '../constants/protocol.dart';

/// Spectrum measurement data (variable FFT points)
class SpectrumData {
  final int centerFreqKhz;
  final int rbwIndex;
  final List<double> powerDbm;
  final DateTime timestamp;
  final int fftPoints;

  SpectrumData({
    required this.centerFreqKhz,
    required this.rbwIndex,
    required this.powerDbm,
    DateTime? timestamp,
    int? fftPoints,
  }) : timestamp = timestamp ?? DateTime.now(),
       fftPoints = fftPoints ?? powerDbm.length;

  /// Parse binary spectrum data (N x int32, Little Endian)
  /// Values are in dBm * 100 (e.g., -5000 = -50.00 dBm)
  factory SpectrumData.fromBinary({
    required Uint8List binaryData,
    required int centerFreqKhz,
    required int rbwIndex,
  }) {
    final byteData = ByteData.sublistView(binaryData);
    final powerDbm = <double>[];
    final numPoints = binaryData.length ~/ 4;

    for (int i = 0; i < numPoints; i++) {
      final rawValue = byteData.getInt32(i * 4, Endian.little);
      powerDbm.add(rawValue / 100.0);
    }

    return SpectrumData(
      centerFreqKhz: centerFreqKhz,
      rbwIndex: rbwIndex,
      powerDbm: powerDbm,
      fftPoints: numPoints,
    );
  }

  /// Get frequency axis values in MHz
  List<double> getFrequencyAxisMhz() {
    final freqResolution = Protocol.sampleRate / fftPoints;
    final centerFreqHz = centerFreqKhz * 1000.0;

    return List.generate(fftPoints, (i) {
      final freqHz = centerFreqHz + (i - fftPoints / 2) * freqResolution;
      return freqHz / 1e6; // Convert to MHz
    });
  }

  /// Get span in MHz (based on actual FFT points)
  double get spanMhz => (Protocol.sampleRate / fftPoints) * fftPoints / 1e6;

  /// Get start frequency in MHz
  double get startFreqMhz => (centerFreqKhz / 1000.0) - (spanMhz / 2);

  /// Get stop frequency in MHz
  double get stopFreqMhz => (centerFreqKhz / 1000.0) + (spanMhz / 2);

  /// Find peak value and index
  ({double power, int index, double freqMhz}) findPeak() {
    double maxPower = double.negativeInfinity;
    int maxIndex = 0;

    for (int i = 0; i < powerDbm.length; i++) {
      if (powerDbm[i] > maxPower) {
        maxPower = powerDbm[i];
        maxIndex = i;
      }
    }

    final freqAxis = getFrequencyAxisMhz();
    return (power: maxPower, index: maxIndex, freqMhz: freqAxis[maxIndex]);
  }

  /// Export to CSV format
  String toCsv() {
    final freqAxis = getFrequencyAxisMhz();
    final buffer = StringBuffer();
    buffer.writeln('Frequency (MHz),Power (dBm)');

    for (int i = 0; i < powerDbm.length; i++) {
      buffer.writeln('${freqAxis[i].toStringAsFixed(6)},${powerDbm[i].toStringAsFixed(2)}');
    }

    return buffer.toString();
  }
}
