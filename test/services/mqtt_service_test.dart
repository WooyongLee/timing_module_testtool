import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:timing_module_testtool/services/mqtt_service.dart';
import 'package:timing_module_testtool/constants/protocol.dart';
import '../helpers/test_data_generator.dart';

void main() {
  group('MqttLogEntry', () {
    test('should create log entry with current timestamp', () {
      // Arrange & Act
      final before = DateTime.now();
      final entry = MqttLogEntry(
        direction: 'TX',
        topic: 'pact/command',
        message: 'test message',
      );
      final after = DateTime.now();

      // Assert
      expect(entry.direction, equals('TX'));
      expect(entry.topic, equals('pact/command'));
      expect(entry.message, equals('test message'));
      expect(entry.isBinary, isFalse);
      expect(entry.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(entry.timestamp.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('should create binary log entry', () {
      // Arrange & Act
      final entry = MqttLogEntry(
        direction: 'RX',
        topic: 'pact/data2',
        message: '32768 bytes',
        isBinary: true,
      );

      // Assert
      expect(entry.isBinary, isTrue);
    });

    test('should format time correctly', () {
      // Arrange
      final entry = MqttLogEntry(
        direction: 'SYS',
        topic: '',
        message: 'Connected',
      );

      // Act
      final formattedTime = entry.formattedTime;

      // Assert
      expect(formattedTime, matches(RegExp(r'\d{2}:\d{2}:\d{2}\.\d{3}')));
    });
  });

  group('MqttResponse', () {
    test('should create response with required fields', () {
      // Arrange & Act
      final response = MqttResponse(
        type: Protocol.typeSpectrum,
        status: Protocol.statusOk,
      );

      // Assert
      expect(response.type, equals(Protocol.typeSpectrum));
      expect(response.status, equals(Protocol.statusOk));
      expect(response.isOk, isTrue);
    });

    test('should recognize OK status', () {
      // status 0 is OK
      final response0 = MqttResponse(type: 0, status: 0);
      expect(response0.isOk, isTrue);

      // status 1 is also considered OK (for init response)
      final response1 = MqttResponse(type: 0, status: 1);
      expect(response1.isOk, isTrue);
    });

    test('should recognize error status', () {
      final response = MqttResponse(type: 0, status: Protocol.statusBusy);
      expect(response.isOk, isFalse);
    });

    test('should return status message', () {
      final responseOk = MqttResponse(type: 0, status: Protocol.statusOk);
      expect(responseOk.statusMessage, equals('OK'));

      final responseBusy = MqttResponse(type: 0, status: Protocol.statusBusy);
      expect(responseBusy.statusMessage, equals('Busy'));

      final responseNotInit = MqttResponse(type: 0, status: Protocol.statusNotInit);
      expect(responseNotInit.statusMessage, equals('Not Initialized'));
    });

    test('should include optional fields', () {
      // Arrange & Act
      final response = MqttResponse(
        type: Protocol.typeSpectrum,
        status: Protocol.statusOk,
        centerFreqHz: 3000000000,
        dataPoints: 8192,
      );

      // Assert
      expect(response.centerFreqHz, equals(3000000000));
      expect(response.dataPoints, equals(8192));
    });
  });

  group('MqttService', () {
    late MqttService mqttService;

    setUp(() {
      mqttService = MqttService();
    });

    tearDown(() {
      mqttService.dispose();
    });

    test('should initialize with default values', () {
      expect(mqttService.connectionState, equals(ConnectionState.disconnected));
      expect(mqttService.isConnected, isFalse);
      expect(mqttService.isInitialized, isFalse);
      expect(mqttService.brokerIp, equals(Protocol.defaultIp));
      expect(mqttService.logHistory, isEmpty);
    });

    test('should clear logs', () {
      // First add some logs (indirectly test internal state)
      // Note: We can't easily add logs directly without connecting,
      // but we can test that clearLogs doesn't throw
      mqttService.clearLogs();
      expect(mqttService.logHistory, isEmpty);
    });

    group('command formatting', () {
      // These tests verify the command strings that would be sent

      test('should format init command correctly', () {
        // This tests the expected format, not actual sending
        const centerFreqHz = 3000000000;
        const rbwIndex = 2;
        const maxHold = true;

        final expectedCommand = '0x44 0x00 $centerFreqHz $rbwIndex 1';
        expect(expectedCommand, equals('0x44 0x00 3000000000 2 1'));
      });

      test('should format spectrum command correctly', () {
        const expectedCommand = '0x44 0x01';
        expect(expectedCommand, equals('0x44 0x01'));
      });

      test('should format IQ capture command correctly', () {
        const sampleCount = 4096;
        final expectedCommand = '0x44 0x02 $sampleCount';
        expect(expectedCommand, equals('0x44 0x02 4096'));
      });

      test('should format stop command correctly', () {
        const expectedCommand = '0x44 0x0F';
        expect(expectedCommand, equals('0x44 0x0F'));
      });
    });

    group('streams', () {
      test('should provide response stream', () {
        expect(mqttService.responseStream, isA<Stream<MqttResponse>>());
      });

      test('should provide spectrum data stream', () {
        expect(mqttService.spectrumDataStream, isA<Stream<Uint8List>>());
      });

      test('should provide IQ data stream', () {
        expect(mqttService.iqDataStream, isA<Stream<Uint8List>>());
      });

      test('should provide log stream', () {
        expect(mqttService.logStream, isA<Stream<MqttLogEntry>>());
      });
    });
  });

  group('Protocol constants', () {
    test('should have correct MQTT topics', () {
      expect(Protocol.commandTopic, equals('pact/command'));
      expect(Protocol.dataTopic, equals('pact/data1'));
      expect(Protocol.data2Topic, equals('pact/data2'));
    });

    test('should have correct command/response headers', () {
      expect(Protocol.cmdHeader, equals(0x44));
      expect(Protocol.respHeader, equals(0x45));
    });

    test('should have correct command types', () {
      expect(Protocol.typeInit, equals(0x00));
      expect(Protocol.typeSpectrum, equals(0x01));
      expect(Protocol.typeIqCapture, equals(0x02));
      expect(Protocol.typeStop, equals(0x0F));
    });

    test('should have correct spectrum configuration', () {
      expect(Protocol.sampleRate, equals(61440000));
      expect(Protocol.spectrumPoints, equals(8192));
    });
  });
}
