/// Device Status Model
/// Based on status_protocol_1.txt and ad9361_manager.c get functions
class DeviceStatus {
  // Frequency settings
  final int currentFrequency; // Hz
  final int samplingFrequency; // Hz
  final int rxLoFrequency; // Hz
  final int txLoFrequency; // Hz

  // Gain/Attenuation
  final int rx1Gain; // dB
  final int rx2Gain; // dB
  final int tx1Attenuation; // mdB (millidB)
  final int tx2Attenuation; // mdB
  final int saAttenuation; // dB
  final int saPreampState; // 0 or 1

  // Temperature
  final int temperature; // °C

  // Bandwidth & Filter
  final int rxRfBandwidth; // Hz
  final int txRfBandwidth; // Hz
  final int firFilterEnable; // 0 or 1

  // Port selection
  final String rxPort; // e.g., "A_BALANCED"
  final String txPort; // e.g., "B"

  // ADI debug settings (meas_type==8 related)
  final int rx1Tx1ModeRxNum; // 1RX-1TX mode RX num
  final int rx1Tx1ModeTxNum; // 1RX-1TX mode TX num
  final int rx2Tx2ModeEnable; // 2RX-2TX mode enable
  final int rxRfPortInputSelect; // RX RF port input select
  final int txLoPowerdown; // TX LO powerdown
  final int outVoltage2Raw; // out_voltage2_raw

  DeviceStatus({
    required this.currentFrequency,
    required this.samplingFrequency,
    required this.rxLoFrequency,
    required this.txLoFrequency,
    required this.rx1Gain,
    required this.rx2Gain,
    required this.tx1Attenuation,
    required this.tx2Attenuation,
    required this.saAttenuation,
    required this.saPreampState,
    required this.temperature,
    required this.rxRfBandwidth,
    required this.txRfBandwidth,
    required this.firFilterEnable,
    required this.rxPort,
    required this.txPort,
    required this.rx1Tx1ModeRxNum,
    required this.rx1Tx1ModeTxNum,
    required this.rx2Tx2ModeEnable,
    required this.rxRfPortInputSelect,
    required this.txLoPowerdown,
    required this.outVoltage2Raw,
  });

  /// Parse device status from MQTT response
  /// Response format: 0x45 0x05 <freq> <sampling_freq> <rx_lo> <tx_lo> <rx1_gain> <rx2_gain>
  ///                  <tx1_atten> <tx2_atten> <sa_att> <preamp> <temp> <rx_bw> <tx_bw> <fir_en>
  ///                  <rx_port> <tx_port> <rx_num> <tx_num> <2rx2tx_en> <port_sel> <tx_pd> <vol2_raw>
  factory DeviceStatus.fromMqttResponse(String response) {
    final parts = response.trim().split(' ');

    if (parts.length < 24) {
      throw FormatException('Invalid status response format: expected at least 24 parts, got ${parts.length}');
    }

    try {
      return DeviceStatus(
        currentFrequency: int.parse(parts[2]),
        samplingFrequency: int.parse(parts[3]),
        rxLoFrequency: int.parse(parts[4]),
        txLoFrequency: int.parse(parts[5]),
        rx1Gain: int.parse(parts[6]),
        rx2Gain: int.parse(parts[7]),
        tx1Attenuation: int.parse(parts[8]),
        tx2Attenuation: int.parse(parts[9]),
        saAttenuation: int.parse(parts[10]),
        saPreampState: int.parse(parts[11]),
        temperature: int.parse(parts[12]),
        rxRfBandwidth: int.parse(parts[13]),
        txRfBandwidth: int.parse(parts[14]),
        firFilterEnable: int.parse(parts[15]),
        rxPort: parts[16],
        txPort: parts[17],
        rx1Tx1ModeRxNum: int.parse(parts[18]),
        rx1Tx1ModeTxNum: int.parse(parts[19]),
        rx2Tx2ModeEnable: int.parse(parts[20]),
        rxRfPortInputSelect: int.parse(parts[21]),
        txLoPowerdown: int.parse(parts[22]),
        outVoltage2Raw: int.parse(parts[23]),
      );
    } catch (e) {
      throw FormatException('Error parsing status response: $e');
    }
  }

  // Helper methods for formatted display
  String get currentFrequencyGhz => (currentFrequency / 1e9).toStringAsFixed(3);
  String get samplingFrequencyMhz => (samplingFrequency / 1e6).toStringAsFixed(2);
  String get rxLoFrequencyGhz => (rxLoFrequency / 1e9).toStringAsFixed(3);
  String get txLoFrequencyGhz => (txLoFrequency / 1e9).toStringAsFixed(3);
  String get rxRfBandwidthMhz => (rxRfBandwidth / 1e6).toStringAsFixed(2);
  String get txRfBandwidthMhz => (txRfBandwidth / 1e6).toStringAsFixed(2);
  String get tx1AttenuationDb => (tx1Attenuation / 1000.0).toStringAsFixed(3);
  String get tx2AttenuationDb => (tx2Attenuation / 1000.0).toStringAsFixed(3);
  String get firFilterStatus => firFilterEnable == 1 ? 'Enabled' : 'Disabled';
  String get preampStatus => saPreampState == 1 ? 'On' : 'Off';
  String get rx2Tx2ModeStatus => rx2Tx2ModeEnable == 1 ? 'Enabled' : 'Disabled';
  String get txLoPowerdownStatus => txLoPowerdown == 1 ? 'Power Down' : 'Active';

  @override
  String toString() {
    return '''
Device Status:
  Current Frequency: $currentFrequencyGhz GHz
  Sampling Frequency: $samplingFrequencyMhz MHz
  RX LO Frequency: $rxLoFrequencyGhz GHz
  TX LO Frequency: $txLoFrequencyGhz GHz

  RX1 Gain: $rx1Gain dB
  RX2 Gain: $rx2Gain dB
  TX1 Attenuation: $tx1AttenuationDb dB
  TX2 Attenuation: $tx2AttenuationDb dB
  SA Attenuation: $saAttenuation dB
  SA Preamp: $preampStatus

  RX RF Bandwidth: $rxRfBandwidthMhz MHz
  TX RF Bandwidth: $txRfBandwidthMhz MHz
  FIR Filter: $firFilterStatus

  RX Port: $rxPort
  TX Port: $txPort

  Temperature: $temperature °C

  ADI Debug Settings:
    1RX-1TX mode RX num: $rx1Tx1ModeRxNum
    1RX-1TX mode TX num: $rx1Tx1ModeTxNum
    2RX-2TX mode: $rx2Tx2ModeStatus
    RX RF port input select: $rxRfPortInputSelect
    TX LO status: $txLoPowerdownStatus
    out_voltage2_raw: $outVoltage2Raw
''';
  }
}
