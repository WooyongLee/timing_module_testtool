/// 61.44MHz Test Protocol Constants
/// Based on test_6144.h and 61_44_TestApp_Guide.md

class Protocol {
  // MQTT Topics
  static const String commandTopic = 'pact/command';
  static const String dataTopic = 'pact/data1';
  static const String data2Topic = 'pact/data2';

  // Command Header
  static const int cmdHeader = 0x44;
  static const int respHeader = 0x45;

  // Command Types
  static const int typeInit = 0x00;
  static const int typeSpectrum = 0x01;
  static const int typeIqCapture = 0x02;
  static const int typeStop = 0x0F;

  // Status Codes
  static const int statusOk = 0;
  static const int statusError = 1;
  static const int statusBusy = 2;
  static const int statusNotInit = 3;

  // Configuration
  static const int sampleRate = 61440000; // 61.44 MHz
  static const int defaultFftLength = 8192;
  static const int maxFftLength = 2457600; // Max FFT length
  static const int maxIqSamples = 2457600; // Max IQ capture length

  // Frequency Range (kHz)
  static const int minFreqKhz = 60000; // 60 MHz
  static const int maxFreqKhz = 6000000; // 6 GHz
  static const int defaultFreqKhz = 2000000; // 2 GHz

  // RBW Options
  static const List<RbwOption> rbwOptions = [
    RbwOption(index: 0, valueHz: 15000, label: '15 kHz'),
    RbwOption(index: 1, valueHz: 30000, label: '30 kHz'),
    RbwOption(index: 2, valueHz: 60000, label: '60 kHz'),
    RbwOption(index: 3, valueHz: 120000, label: '120 kHz'),
  ];

  static const int defaultRbwIndex = 2; // 60 kHz

  // Default MQTT Settings
  static const int mqttPort = 1883;
  static const String defaultIp = '192.168.123.8';

  // Get status message
  static String getStatusMessage(int status) {
    switch (status) {
      case statusOk:
        return 'OK';
      case statusError:
        return 'Error';
      case statusBusy:
        return 'Busy';
      case statusNotInit:
        return 'Not Initialized';
      default:
        return 'Unknown';
    }
  }
}

class RbwOption {
  final int index;
  final int valueHz;
  final String label;

  const RbwOption({
    required this.index,
    required this.valueHz,
    required this.label,
  });
}
