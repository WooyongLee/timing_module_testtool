import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class IqView extends StatelessWidget {
  const IqView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              // Title bar with legend
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timeline, size: 20, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Text(
                      'IQ Data View',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Legend
                    _buildLegend(),
                  ],
                ),
              ),
              // Chart area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildIqChart(appState),
                ),
              ),
              // Bottom info bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    // fs info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'fs = 61.44 MHz',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // IQ data info
                    if (appState.iqData != null)
                      _buildIqInfo(appState),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 3,
          color: Colors.blue,
        ),
        const SizedBox(width: 4),
        const Text('I Data', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 16),
        Container(
          width: 20,
          height: 3,
          color: Colors.red,
        ),
        const SizedBox(width: 4),
        const Text('Q Data', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildIqChart(AppState appState) {
    if (appState.iqData == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[700]!),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timeline,
                size: 64,
                color: Colors.purple.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No IQ Data',
                style: TextStyle(
                  color: Colors.purple.withOpacity(0.5),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Click "Start" to capture IQ data',
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final iqData = appState.iqData!;
    final iSpots = _createSpots(iqData.iChannel);
    final qSpots = _createSpots(iqData.qChannel);

    // Calculate Y axis range
    final allValues = [...iqData.iChannel, ...iqData.qChannel];
    final maxVal = allValues.reduce((a, b) => a > b ? a : b).toDouble();
    final minVal = allValues.reduce((a, b) => a < b ? a : b).toDouble();
    final yMax = (maxVal * 1.1).ceilToDouble();
    final yMin = (minVal * 1.1).floorToDouble();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      padding: const EdgeInsets.only(top: 16, right: 24, bottom: 8, left: 8),
      child: LineChart(
        LineChartData(
          minY: yMin,
          maxY: yMax,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
            horizontalInterval: _calculateYInterval(yMax - yMin),
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
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: _calculateYInterval(yMax - yMin),
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
                'Sample',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              sideTitles: const SideTitles(showTitles: false),
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
            // I channel (blue)
            LineChartBarData(
              spots: iSpots,
              isCurved: false,
              color: Colors.blue,
              barWidth: 1.5,
              isStrokeCapRound: false,
              dotData: const FlDotData(show: false),
            ),
            // Q channel (red)
            LineChartBarData(
              spots: qSpots,
              isCurved: false,
              color: Colors.red,
              barWidth: 1.5,
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
                  final label = spot.barIndex == 0 ? 'I' : 'Q';
                  return LineTooltipItem(
                    '$label: ${spot.y.toInt()}',
                    TextStyle(
                      color: spot.barIndex == 0 ? Colors.blue : Colors.red,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  List<FlSpot> _createSpots(List<int> data) {
    final spots = <FlSpot>[];
    // Downsample for performance
    final maxPoints = 1024;
    final step = (data.length / maxPoints).ceil().clamp(1, data.length);

    for (int i = 0; i < data.length; i += step) {
      spots.add(FlSpot(i.toDouble(), data[i].toDouble()));
    }

    return spots;
  }

  double _calculateYInterval(double range) {
    if (range > 50000) return 10000;
    if (range > 20000) return 5000;
    if (range > 10000) return 2000;
    if (range > 5000) return 1000;
    return 500;
  }

  Widget _buildIqInfo(AppState appState) {
    final iqData = appState.iqData!;
    final iMax = iqData.iChannel.reduce((a, b) => a > b ? a : b);
    final qMax = iqData.qChannel.reduce((a, b) => a > b ? a : b);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'I : $iMax',
            style: TextStyle(fontSize: 11, color: Colors.blue[700]),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Q : $qMax',
            style: TextStyle(fontSize: 11, color: Colors.red[700]),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Samples: ${iqData.sampleCount}',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
