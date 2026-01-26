import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class IqView extends StatefulWidget {
  const IqView({super.key});

  @override
  State<IqView> createState() => _IqViewState();
}

class _IqViewState extends State<IqView> {
  // Zoom state
  double? _zoomMinX;
  double? _zoomMaxX;

  // Selection state for drag-to-zoom
  bool _isSelecting = false;
  Offset? _selectionStart;
  Offset? _selectionEnd;

  // Chart area key for coordinate conversion
  final GlobalKey _chartKey = GlobalKey();

  // Chart padding (must match the padding in _buildIqChart)
  static const double _chartLeftPadding = 8;
  static const double _chartRightPadding = 24;
  static const double _chartTopPadding = 16;
  static const double _chartBottomPadding = 8;

  void _resetZoom() {
    setState(() {
      _zoomMinX = null;
      _zoomMaxX = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              // Title bar with legend and zoom controls
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
                    const SizedBox(width: 16),
                    // Zoom indicator and reset button
                    if (_zoomMinX != null && _zoomMaxX != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, size: 14, color: Colors.orange[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Zoomed: ${_zoomMinX!.toInt()} - ${_zoomMaxX!.toInt()}',
                              style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 24,
                        child: OutlinedButton.icon(
                          onPressed: _resetZoom,
                          icon: const Icon(Icons.zoom_out_map, size: 14),
                          label: const Text('Reset', style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: Colors.orange[700],
                            side: BorderSide(color: Colors.orange[300]!),
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Drag to zoom',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                    const Spacer(),
                    // Legend
                    _buildLegend(),
                  ],
                ),
              ),
              // Chart area with selection overlay
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildZoomableChart(appState),
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

  Widget _buildZoomableChart(AppState appState) {
    if (appState.iqData == null) {
      return _buildEmptyChart();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (details) {
            setState(() {
              _isSelecting = true;
              _selectionStart = details.localPosition;
              _selectionEnd = details.localPosition;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _selectionEnd = details.localPosition;
            });
          },
          onPanEnd: (details) {
            if (_selectionStart != null && _selectionEnd != null) {
              _applyZoom(appState, constraints);
            }
            setState(() {
              _isSelecting = false;
              _selectionStart = null;
              _selectionEnd = null;
            });
          },
          child: Stack(
            key: _chartKey,
            children: [
              // The actual chart
              _buildIqChart(appState),
              // Selection overlay
              if (_isSelecting && _selectionStart != null && _selectionEnd != null)
                _buildSelectionOverlay(),
            ],
          ),
        );
      },
    );
  }

  void _applyZoom(AppState appState, BoxConstraints constraints) {
    if (_selectionStart == null || _selectionEnd == null) return;

    final iqData = appState.iqData;
    if (iqData == null) return;

    // Chart area dimensions (accounting for padding)
    final chartWidth = constraints.maxWidth - _chartLeftPadding - _chartRightPadding;

    // Get X coordinates (horizontal only zoom)
    final startX = (_selectionStart!.dx - _chartLeftPadding).clamp(0.0, chartWidth);
    final endX = (_selectionEnd!.dx - _chartLeftPadding).clamp(0.0, chartWidth);

    // Minimum selection width (at least 10 pixels)
    if ((endX - startX).abs() < 10) return;

    // Calculate sample range
    final totalSamples = iqData.sampleCount.toDouble();
    final currentMinX = _zoomMinX ?? 0;
    final currentMaxX = _zoomMaxX ?? totalSamples;
    final currentRange = currentMaxX - currentMinX;

    final leftRatio = startX.clamp(0, chartWidth) / chartWidth;
    final rightRatio = endX.clamp(0, chartWidth) / chartWidth;

    final newMinX = currentMinX + currentRange * (startX < endX ? leftRatio : rightRatio);
    final newMaxX = currentMinX + currentRange * (startX < endX ? rightRatio : leftRatio);

    // Ensure valid range
    if (newMaxX - newMinX < 10) return; // Minimum 10 samples visible

    setState(() {
      _zoomMinX = newMinX.clamp(0, totalSamples);
      _zoomMaxX = newMaxX.clamp(0, totalSamples);
    });
  }

  Widget _buildSelectionOverlay() {
    final left = _selectionStart!.dx < _selectionEnd!.dx
        ? _selectionStart!.dx
        : _selectionEnd!.dx;
    final right = _selectionStart!.dx > _selectionEnd!.dx
        ? _selectionStart!.dx
        : _selectionEnd!.dx;

    return Positioned.fill(
      child: CustomPaint(
        painter: _SelectionPainter(
          left: left,
          right: right,
        ),
      ),
    );
  }

  Widget _buildEmptyChart() {
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
              'Click "IQ Capture" to capture IQ data',
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

  Widget _buildIqChart(AppState appState) {
    final iqData = appState.iqData!;

    // Determine visible range
    final totalSamples = iqData.sampleCount.toDouble();
    final minX = _zoomMinX ?? 0;
    final maxX = _zoomMaxX ?? totalSamples;

    // Get data for visible range
    final startIdx = minX.floor().clamp(0, iqData.sampleCount - 1);
    final endIdx = maxX.ceil().clamp(0, iqData.sampleCount);

    final visibleI = iqData.iChannel.sublist(startIdx, endIdx);
    final visibleQ = iqData.qChannel.sublist(startIdx, endIdx);

    final iSpots = _createSpots(visibleI, startIdx);
    final qSpots = _createSpots(visibleQ, startIdx);

    // Calculate Y axis range from visible data
    final allValues = [...visibleI, ...visibleQ];
    if (allValues.isEmpty) return _buildEmptyChart();

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
      padding: EdgeInsets.only(
        top: _chartTopPadding,
        right: _chartRightPadding,
        bottom: _chartBottomPadding,
        left: _chartLeftPadding,
      ),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
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
                reservedSize: 55,
                interval: _calculateYInterval(yMax - yMin),
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      _formatYLabel(value),
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
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: _calculateXInterval(maxX - minX),
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatXLabel(value),
                    style: const TextStyle(color: Colors.grey, fontSize: 9),
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
            enabled: !_isSelecting,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => Colors.black87,
              tooltipRoundedRadius: 4,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (touchedSpots) {
                if (touchedSpots.isEmpty) return [];

                final sampleIndex = touchedSpots.first.x.toInt();

                // Return exactly same number of items as touchedSpots
                return touchedSpots.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final spot = entry.value;
                  final label = spot.barIndex == 0 ? 'I' : 'Q';
                  final color = spot.barIndex == 0 ? Colors.blue : Colors.red;

                  // First item includes sample number
                  if (idx == 0) {
                    return LineTooltipItem(
                      'Sample: $sampleIndex\n$label: ${spot.y.toInt()}',
                      TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }

                  return LineTooltipItem(
                    '$label: ${spot.y.toInt()}',
                    TextStyle(
                      color: color,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
            handleBuiltInTouches: true,
          ),
        ),
      ),
    );
  }

  List<FlSpot> _createSpots(List<int> data, int startIndex) {
    final spots = <FlSpot>[];
    // Downsample for performance
    final maxPoints = 2048;
    final step = (data.length / maxPoints).ceil().clamp(1, data.length);

    for (int i = 0; i < data.length; i += step) {
      spots.add(FlSpot((startIndex + i).toDouble(), data[i].toDouble()));
    }

    return spots;
  }

  double _calculateYInterval(double range) {
    // Target approximately 5-10 labels on the Y axis
    if (range <= 0) return 1;

    // Calculate a nice interval based on the range
    final rawInterval = range / 6; // Target ~6 intervals

    // Find the magnitude (power of 10)
    final magnitude = _getMagnitude(rawInterval);

    // Normalize to 1-10 range
    final normalized = rawInterval / magnitude;

    // Round to a nice number
    double niceInterval;
    if (normalized <= 1) {
      niceInterval = 1;
    } else if (normalized <= 2) {
      niceInterval = 2;
    } else if (normalized <= 5) {
      niceInterval = 5;
    } else {
      niceInterval = 10;
    }

    return niceInterval * magnitude;
  }

  double _calculateXInterval(double range) {
    // Target approximately 5-8 labels on the X axis
    if (range <= 0) return 1;

    final rawInterval = range / 6; // Target ~6 intervals

    final magnitude = _getMagnitude(rawInterval);
    final normalized = rawInterval / magnitude;

    double niceInterval;
    if (normalized <= 1) {
      niceInterval = 1;
    } else if (normalized <= 2) {
      niceInterval = 2;
    } else if (normalized <= 5) {
      niceInterval = 5;
    } else {
      niceInterval = 10;
    }

    return niceInterval * magnitude;
  }

  double _getMagnitude(double value) {
    if (value == 0) return 1;
    final log10Val = math.log(value.abs()) / math.ln10;
    return math.pow(10, log10Val.floor()).toDouble();
  }

  String _formatYLabel(double value) {
    final absValue = value.abs();
    if (absValue >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}G';
    } else if (absValue >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (absValue >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toInt().toString();
  }

  String _formatXLabel(double value) {
    final absValue = value.abs();
    if (absValue >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (absValue >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toInt().toString();
  }

  Widget _buildIqInfo(AppState appState) {
    final iqData = appState.iqData!;
    final iMax = iqData.iChannel.reduce((a, b) => a > b ? a : b);
    final iMin = iqData.iChannel.reduce((a, b) => a < b ? a : b);
    final qMax = iqData.qChannel.reduce((a, b) => a > b ? a : b);
    final qMin = iqData.qChannel.reduce((a, b) => a < b ? a : b);
    final byteSize = appState.iqByteSize;

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
            'I max: $iMax, min: $iMin',
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
            'Q max: $qMax, min: $qMin',
            style: TextStyle(fontSize: 11, color: Colors.red[700]),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Samples: ${iqData.sampleCount} ($byteSize bytes)',
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for selection overlay
class _SelectionPainter extends CustomPainter {
  final double left;
  final double right;

  _SelectionPainter({required this.left, required this.right});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw semi-transparent overlay on unselected areas
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Left unselected area
    canvas.drawRect(
      Rect.fromLTRB(0, 0, left, size.height),
      overlayPaint,
    );

    // Right unselected area
    canvas.drawRect(
      Rect.fromLTRB(right, 0, size.width, size.height),
      overlayPaint,
    );

    // Draw selection border
    final borderPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromLTRB(left, 0, right, size.height),
      borderPaint,
    );

    // Draw selection fill
    final fillPaint = Paint()
      ..color = Colors.orange.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTRB(left, 0, right, size.height),
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) {
    return left != oldDelegate.left || right != oldDelegate.right;
  }
}
