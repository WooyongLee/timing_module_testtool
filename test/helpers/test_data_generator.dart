import 'dart:math';
import 'dart:typed_data';

/// Test data generator for creating dummy spectrum and IQ data
class TestDataGenerator {
  static final _random = Random(42); // Fixed seed for reproducibility

  /// Generate dummy spectrum binary data (8192 x int32, Little Endian)
  /// Simulates a spectrum with a peak at a specified frequency bin
  /// Values are dBm * 100 (e.g., -5000 = -50.00 dBm)
  static Uint8List generateSpectrumData({
    int points = 8192,
    double noiseFloorDbm = -80.0,
    double peakDbm = -20.0,
    int peakBin = 4096, // Center by default
    int peakWidth = 50, // Bins around peak
  }) {
    final byteData = ByteData(points * 4);

    for (int i = 0; i < points; i++) {
      double powerDbm;

      // Calculate distance from peak
      final distFromPeak = (i - peakBin).abs();

      if (distFromPeak <= peakWidth) {
        // Gaussian-like peak shape
        final ratio = distFromPeak / peakWidth;
        powerDbm = peakDbm - (ratio * ratio * (peakDbm - noiseFloorDbm));
      } else {
        // Noise floor with some variation
        powerDbm = noiseFloorDbm + (_random.nextDouble() - 0.5) * 5;
      }

      // Convert to int (dBm * 100)
      final rawValue = (powerDbm * 100).round();
      byteData.setInt32(i * 4, rawValue, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  /// Generate dummy IQ binary data (I16, Q16 pairs, Little Endian)
  /// Simulates a sine wave with specified frequency
  static Uint8List generateIqData({
    int sampleCount = 4096,
    double frequencyRatio = 0.1, // Normalized frequency (cycles per sample)
    int amplitude = 8000, // 16-bit signed max is 32767
    double noiseLevel = 100, // Noise amplitude
  }) {
    final byteData = ByteData(sampleCount * 4);

    for (int i = 0; i < sampleCount; i++) {
      // Generate I and Q for a complex sinusoid
      final phase = 2 * pi * frequencyRatio * i;
      final iValue = (amplitude * cos(phase) +
              (_random.nextDouble() - 0.5) * noiseLevel * 2)
          .round()
          .clamp(-32768, 32767);
      final qValue = (amplitude * sin(phase) +
              (_random.nextDouble() - 0.5) * noiseLevel * 2)
          .round()
          .clamp(-32768, 32767);

      byteData.setInt16(i * 4, iValue, Endian.little);
      byteData.setInt16(i * 4 + 2, qValue, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  /// Generate spectrum data with multiple peaks
  static Uint8List generateMultiPeakSpectrumData({
    int points = 8192,
    double noiseFloorDbm = -80.0,
    List<({int bin, double dbm, int width})>? peaks,
  }) {
    peaks ??= [
      (bin: 2048, dbm: -30.0, width: 30),
      (bin: 4096, dbm: -25.0, width: 40),
      (bin: 6144, dbm: -35.0, width: 25),
    ];

    final byteData = ByteData(points * 4);

    for (int i = 0; i < points; i++) {
      double powerDbm = noiseFloorDbm + (_random.nextDouble() - 0.5) * 3;

      // Add contribution from each peak
      for (final peak in peaks) {
        final distFromPeak = (i - peak.bin).abs();
        if (distFromPeak <= peak.width * 2) {
          final ratio = distFromPeak / peak.width;
          final peakContrib = peak.dbm * exp(-ratio * ratio * 2);
          // Use logarithmic addition for power
          powerDbm = 10 * log(pow(10, powerDbm / 10) + pow(10, peakContrib / 10)) / ln10;
        }
      }

      final rawValue = (powerDbm * 100).round();
      byteData.setInt32(i * 4, rawValue, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  /// Generate IQ data with multiple frequency components
  static Uint8List generateMultiToneIqData({
    int sampleCount = 4096,
    List<({double freqRatio, int amplitude})>? tones,
  }) {
    tones ??= [
      (freqRatio: 0.05, amplitude: 5000),
      (freqRatio: 0.15, amplitude: 3000),
      (freqRatio: 0.25, amplitude: 2000),
    ];

    final byteData = ByteData(sampleCount * 4);

    for (int i = 0; i < sampleCount; i++) {
      double iSum = 0;
      double qSum = 0;

      for (final tone in tones) {
        final phase = 2 * pi * tone.freqRatio * i;
        iSum += tone.amplitude * cos(phase);
        qSum += tone.amplitude * sin(phase);
      }

      // Add some noise
      iSum += (_random.nextDouble() - 0.5) * 200;
      qSum += (_random.nextDouble() - 0.5) * 200;

      final iValue = iSum.round().clamp(-32768, 32767);
      final qValue = qSum.round().clamp(-32768, 32767);

      byteData.setInt16(i * 4, iValue, Endian.little);
      byteData.setInt16(i * 4 + 2, qValue, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  /// Create text response string for Init command
  static String createInitResponse({
    int status = 1,
    int centerFreqHz = 3000000000,
    int rbwIndex = 2,
    int maxHold = 0,
  }) {
    return '0x45 $status $centerFreqHz $rbwIndex $maxHold';
  }

  /// Create text response string for Spectrum header
  static String createSpectrumHeaderResponse({int dataPoints = 8192}) {
    return '0x45 0x01 $dataPoints';
  }

  /// Create text response string for IQ header
  static String createIqHeaderResponse({int sampleCount = 4096}) {
    return '0x45 0x02 $sampleCount';
  }

  /// Create text response string for Stop command
  static String createStopResponse() {
    return '0x45 0x0F';
  }
}
