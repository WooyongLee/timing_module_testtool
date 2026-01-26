import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/spectrum_data.dart';
import '../models/iq_data.dart';

class FileService {
  /// Save spectrum data to CSV file
  static Future<String?> saveSpectrumCsv(SpectrumData data) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final defaultName = 'spectrum_${data.centerFreqKhz}kHz_$timestamp.csv';

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Spectrum Data',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (outputPath == null) return null;

      // Ensure .csv extension
      if (!outputPath.endsWith('.csv')) {
        outputPath = '$outputPath.csv';
      }

      final file = File(outputPath);
      await file.writeAsString(data.toCsv());

      debugPrint('Spectrum saved to: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('Error saving spectrum: $e');
      return null;
    }
  }

  /// Save IQ data to CSV file
  static Future<String?> saveIqCsv(IqData data) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final defaultName = 'iq_${data.centerFreqKhz}kHz_${data.sampleCount}samples_$timestamp.csv';

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save IQ Data',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (outputPath == null) return null;

      if (!outputPath.endsWith('.csv')) {
        outputPath = '$outputPath.csv';
      }

      final file = File(outputPath);
      await file.writeAsString(data.toCsv());

      debugPrint('IQ data saved to: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('Error saving IQ data: $e');
      return null;
    }
  }

  /// Save IQ data to binary file
  static Future<String?> saveIqBinary(IqData data) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final defaultName = 'iq_${data.centerFreqKhz}kHz_${data.sampleCount}samples_$timestamp.bin';

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save IQ Binary Data',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['bin'],
      );

      if (outputPath == null) return null;

      if (!outputPath.endsWith('.bin')) {
        outputPath = '$outputPath.bin';
      }

      final file = File(outputPath);
      final bytes = BytesBuilder();

      for (int i = 0; i < data.sampleCount; i++) {
        // Write I (16-bit, little endian)
        final iVal = data.iChannel[i];
        bytes.addByte(iVal & 0xFF);
        bytes.addByte((iVal >> 8) & 0xFF);

        // Write Q (16-bit, little endian)
        final qVal = data.qChannel[i];
        bytes.addByte(qVal & 0xFF);
        bytes.addByte((qVal >> 8) & 0xFF);
      }

      await file.writeAsBytes(bytes.toBytes());

      debugPrint('IQ binary saved to: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('Error saving IQ binary: $e');
      return null;
    }
  }

  /// Save FFT spectrum data to text file (auto path: executable/fft_data/YYYYMMDD/HHMMSS.txt)
  static Future<String?> saveFftToAutoPath(SpectrumData data) async {
    try {
      // Get executable directory
      final executablePath = Platform.resolvedExecutable;
      final executableDir = path.dirname(executablePath);

      // Get current date and time
      final now = DateTime.now();
      final dateFolder = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final fileName = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.txt';

      // Create directory path: executable/fft_data/YYYYMMDD/
      final fftDataDir = path.join(executableDir, 'fft_data', dateFolder);
      final directory = Directory(fftDataDir);

      // Create directories if they don't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        debugPrint('Created directory: $fftDataDir');
      }

      // Create full file path
      final filePath = path.join(fftDataDir, fileName);
      final file = File(filePath);

      // Build FFT data content (one value per line)
      final buffer = StringBuffer();

      // Add header information
      buffer.writeln('# FFT Spectrum Data');
      buffer.writeln('# Center Frequency: ${data.centerFreqKhz} kHz');
      buffer.writeln('# RBW Index: ${data.rbwIndex}');
      buffer.writeln('# FFT Points: ${data.fftPoints}');
      buffer.writeln('# Start Frequency: ${data.startFreqMhz.toStringAsFixed(3)} MHz');
      buffer.writeln('# Stop Frequency: ${data.stopFreqMhz.toStringAsFixed(3)} MHz');
      buffer.writeln('# Timestamp: ${now.toIso8601String()}');
      buffer.writeln('# Format: Power (dBm)');
      buffer.writeln('#');

      // Write FFT values (one per line)
      for (final powerDbm in data.powerDbm) {
        buffer.writeln(powerDbm.toStringAsFixed(6));
      }

      // Write to file
      await file.writeAsString(buffer.toString());

      debugPrint('FFT data saved to: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('Error saving FFT data: $e');
      return null;
    }
  }
}
