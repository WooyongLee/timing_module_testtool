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

  // Command Types (existing 0x00-0x0F)
  static const int typeInit = 0x00;
  static const int typeSpectrum = 0x01;
  static const int typeIqCapture = 0x02;
  static const int typeStop = 0x0F;
  static const int typeRepeatedSpectrum = 0x04;
  static const int typeStatusQuery = 0x05;

  // T-Sync ACQ command types (0x60-0x6A)
  static const int acqInit    = 0x60;
  static const int acqParam   = 0x61;
  static const int acqRun     = 0x62;
  static const int acqStatus  = 0x63;
  static const int acqResult  = 0x64;
  static const int acqLoop    = 0x65;
  static const int acqStop    = 0x66;
  static const int acqSetRf   = 0x67;
  static const int acqSetPd   = 0x68;
  static const int acqVersion = 0x69;
  static const int acqSaveIq  = 0x6A;

  // ACQ lock state values
  static const int lockUnlock   = 0;
  static const int lockLocked   = 1;
  static const int lockHoldover = 3;

  // ACQ error response indicator
  static const int acqRespError = 0xFF;

  // ACQ state machine values
  // 1=POWERON, 2=INIT, 3=TRANSIENT, 4=LOCK1, 5=LOCK2,
  // 6=HOLDOVER, 7=HOLDOVER2, 8=HOLDOVER3
  static const Map<int, String> acqStateNames = {
    1: 'POWERON',
    2: 'INIT',
    3: 'TRANSIENT',
    4: 'LOCK1',
    5: 'LOCK2',
    6: 'HOLDOVER',
    7: 'HOLDOVER2',
    8: 'HOLDOVER3',
  };

  static const Map<int, String> acqLockNames = {
    0: 'UNLOCK',
    1: 'LOCK',
    3: 'HOLDOVER',
  };

  // FTP settings for IQ file download
  static const int ftpPort = 21;
  static const String ftpRemoteBase = '/run/media/mmcblk0p1/capture_data';

  // Status Codes
  static const int statusOk = 0;
  static const int statusError = 1;
  static const int statusBusy = 2;
  static const int statusNotInit = 3;

  // Configuration
  static const int sampleRate = 61440000; // 61.44 MHz
  static const int defaultFftLength = 8192;
  static const int maxFftLength = 65536; // Max FFT length
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
    RbwOption(index: 4, valueHz: 0, label: '- kHz (from FFT Length)'),
  ];

  static const int defaultRbwIndex = 2; // 60 kHz

  // Default MQTT Settings
  static const int mqttPort = 1883;
  static const String defaultIp = '192.168.123.27';

  // TCP Server Settings
  static const int tcpServerPort = 9000;
  static const int tcpMagic      = 0xABCD1234; // magic, little-endian on wire
  static const int tcpTypeCmdReq = 0x10;       // Flutter → device (command)
  static const int tcpTypeStrResp = 0x01;      // device → Flutter (text)
  static const int tcpTypeBinData = 0x02;      // device → Flutter (binary)
  static const int tcpHeaderSize = 12;         // magic(4)+type(1)+pad(3)+length(4)

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
