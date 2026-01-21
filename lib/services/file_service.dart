import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
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
}
