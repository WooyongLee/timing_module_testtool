import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/spectrum_data.dart';

class SpectrumChart extends StatelessWidget {
  final SpectrumData? spectrumData;
  final SpectrumData? maxHoldData;
  final double yMin;
  final double yMax;
  final bool showPeakMarker;
  final int downsampleFactor;

  const SpectrumChart({
    super.key,
    this.spectrumData,
    this.maxHoldData,
    this.yMin = 40,
    this.yMax = 160,
    this.showPeakMarker = true,
    this.downsampleFactor = 8, // 8192 / 8 = 1024 points for display
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      padding: const EdgeInsets.only(top: 16, right: 24, bottom: 8, left: 8),
      child: spectrumData == null
          ? _buildEmptyChart()
          : _buildSpectrumChart(),
    );
  }

  Widget _buildEmptyChart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart,
            size: 64,
            color: Colors.green.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Spectrum Data',
            style: TextStyle(
              color: Colors.green.withOpacity(0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Single" or "Continuous" to start measurement',
            style: TextStyle(
              color: Colors.grey.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectrumChart() {
    final spots = _createSpots(spectrumData!);
    final maxHoldSpots = maxHoldData != null ? _createSpots(maxHoldData!) : null;
    final peak = spectrumData!.findPeak();

    return LineChart(
      LineChartData(
        minX: spectrumData!.startFreqMhz,
        maxX: spectrumData!.stopFreqMhz,
        minY: yMin,
        maxY: yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          horizontalInterval: 10,
          verticalInterval: _calculateVerticalInterval(),
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Text(
              'dBm',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              interval: 20,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    value.toInt().toString(),
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text(
              'Frequency (MHz)',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: _calculateVerticalInterval(),
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    value.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey[600]!),
        ),
        lineBarsData: [
          // Main spectrum trace
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.greenAccent,
            barWidth: 1,
            isStrokeCapRound: false,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withOpacity(0.1),
            ),
          ),
          // MaxHold trace
          if (maxHoldSpots != null)
            LineChartBarData(
              spots: maxHoldSpots,
              isCurved: false,
              color: Colors.yellow.withOpacity(0.7),
              barWidth: 1,
              isStrokeCapRound: false,
              dotData: const FlDotData(show: false),
            ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.black87,
            tooltipRoundedRadius: 4,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.x.toStringAsFixed(3)} MHz\n${spot.y.toStringAsFixed(1)} dBm',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
        extraLinesData: showPeakMarker
            ? ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: peak.freqMhz,
                    color: Colors.red.withOpacity(0.7),
                    strokeWidth: 1,
                    dashArray: [5, 5],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      labelResolver: (line) =>
                          'Peak: ${peak.power.toStringAsFixed(1)} dBm\n${peak.freqMhz.toStringAsFixed(3)} MHz',
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  List<FlSpot> _createSpots(SpectrumData data) {
    final freqAxis = data.getFrequencyAxisMhz();
    final spots = <FlSpot>[];

    // Downsample for better performance
    for (int i = 0; i < data.powerDbm.length; i += downsampleFactor) {
      // Find max value in this segment for peak preservation
      double maxVal = data.powerDbm[i];
      for (int j = 1; j < downsampleFactor && i + j < data.powerDbm.length; j++) {
        if (data.powerDbm[i + j] > maxVal) {
          maxVal = data.powerDbm[i + j];
        }
      }
      spots.add(FlSpot(freqAxis[i], maxVal.clamp(yMin, yMax)));
    }

    return spots;
  }

  double _calculateVerticalInterval() {
    if (spectrumData == null) return 10;
    final span = spectrumData!.spanMhz;
    if (span > 50) return 10;
    if (span > 20) return 5;
    if (span > 10) return 2;
    return 1;
  }
}
