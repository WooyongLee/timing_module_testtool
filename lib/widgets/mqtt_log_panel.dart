import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mqtt_service.dart';

class MqttLogPanel extends StatefulWidget {
  const MqttLogPanel({super.key});

  @override
  State<MqttLogPanel> createState() => _MqttLogPanelState();
}

class _MqttLogPanelState extends State<MqttLogPanel> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttService>(
      builder: (context, mqtt, child) {
        // Auto scroll to bottom when new logs arrive
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_autoScroll && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });

        return Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF1e1e1e),
            border: Border(top: BorderSide(color: Colors.grey[700]!)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2d2d2d),
                  border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    const Text(
                      'MQTT Log',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '(${mqtt.logHistory.length} entries)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    // Auto scroll toggle
                    InkWell(
                      onTap: () => setState(() => _autoScroll = !_autoScroll),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _autoScroll ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 14,
                            color: _autoScroll ? Colors.blue : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Auto-scroll',
                            style: TextStyle(
                              fontSize: 11,
                              color: _autoScroll ? Colors.blue : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Clear button
                    InkWell(
                      onTap: () => mqtt.clearLogs(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.clear_all,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Clear',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Log content
              Expanded(
                child: mqtt.logHistory.isEmpty
                    ? Center(
                        child: Text(
                          'No log entries',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(4),
                        itemCount: mqtt.logHistory.length,
                        itemBuilder: (context, index) {
                          return _buildLogEntry(mqtt.logHistory[index]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogEntry(MqttLogEntry entry) {
    Color dirColor;
    String dirLabel;

    switch (entry.direction) {
      case 'TX':
        dirColor = Colors.green;
        dirLabel = 'TX';
        break;
      case 'RX':
        dirColor = Colors.blue;
        dirLabel = 'RX';
        break;
      case 'SYS':
        dirColor = Colors.orange;
        dirLabel = 'SYS';
        break;
      default:
        dirColor = Colors.grey;
        dirLabel = '??';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 85,
            child: Text(
              entry.formattedTime,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.grey[500],
              ),
            ),
          ),
          // Direction badge
          Container(
            width: 28,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: dirColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              dirLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: dirColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Topic
          if (entry.topic.isNotEmpty) ...[
            Text(
              entry.topic,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.purple[300],
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Message
          Expanded(
            child: Text(
              entry.isBinary ? '[Binary] ${entry.message}' : entry.message,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: entry.isBinary ? Colors.amber : Colors.grey[300],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
