import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device_status.dart';

class DeviceStatusDialog extends StatelessWidget {
  final DeviceStatus status;

  const DeviceStatusDialog({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                const Icon(Icons.info_outline, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Device Status',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection('Frequency Settings', [
                      _buildInfoRow('Current Frequency', '${status.currentFrequencyGhz} GHz'),
                      _buildInfoRow('Sampling Frequency', '${status.samplingFrequencyMhz} MHz'),
                      _buildInfoRow('RX LO Frequency', '${status.rxLoFrequencyGhz} GHz'),
                      _buildInfoRow('TX LO Frequency', '${status.txLoFrequencyGhz} GHz'),
                    ]),
                    const SizedBox(height: 16),

                    _buildSection('Gain / Attenuation', [
                      _buildInfoRow('RX1 Gain', '${status.rx1Gain} dB'),
                      _buildInfoRow('RX2 Gain', '${status.rx2Gain} dB'),
                      _buildInfoRow('TX1 Attenuation', '${status.tx1AttenuationDb} dB'),
                      _buildInfoRow('TX2 Attenuation', '${status.tx2AttenuationDb} dB'),
                      _buildInfoRow('SA Attenuation', '${status.saAttenuation} dB'),
                      _buildInfoRow('SA Preamp State', status.preampStatus),
                    ]),
                    const SizedBox(height: 16),

                    _buildSection('Bandwidth & Filter', [
                      _buildInfoRow('RX RF Bandwidth', '${status.rxRfBandwidthMhz} MHz'),
                      _buildInfoRow('TX RF Bandwidth', '${status.txRfBandwidthMhz} MHz'),
                      _buildInfoRow('FIR Filter', status.firFilterStatus),
                    ]),
                    const SizedBox(height: 16),

                    _buildSection('Port Selection', [
                      _buildInfoRow('RX Port', status.rxPort),
                      _buildInfoRow('TX Port', status.txPort),
                    ]),
                    const SizedBox(height: 16),

                    _buildSection('Temperature', [
                      _buildInfoRow('AD9361 Temperature', '${status.temperature} °C'),
                    ]),
                    const SizedBox(height: 16),

                    _buildSection('ADI Debug Settings (meas_type==8)', [
                      _buildInfoRow('1RX-1TX mode RX num', '${status.rx1Tx1ModeRxNum}'),
                      _buildInfoRow('1RX-1TX mode TX num', '${status.rx1Tx1ModeTxNum}'),
                      _buildInfoRow('2RX-2TX mode', status.rx2Tx2ModeStatus),
                      _buildInfoRow('RX RF port input select', '${status.rxRfPortInputSelect}'),
                      _buildInfoRow('TX LO status', status.txLoPowerdownStatus),
                      _buildInfoRow('out_voltage2_raw', '${status.outVoltage2Raw}'),
                    ]),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _copyToClipboard(context),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy All'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: status.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Status copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }
}
