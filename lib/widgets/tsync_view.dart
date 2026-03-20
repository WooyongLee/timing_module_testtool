import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/tsync_data.dart';
import '../constants/protocol.dart';

class TsyncView extends StatelessWidget {
  const TsyncView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final results = appState.tsyncResults;
        final latest  = results.isNotEmpty ? results.last : null;

        return Container(
          color: const Color(0xFF1E1E1E),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Title bar ───────────────────────────────────────────────
              _TitleBar(appState: appState),

              // ── Status summary row ──────────────────────────────────────
              _StatusSummary(latest: latest, appState: appState),

              const Divider(height: 1, color: Color(0xFF3A3A3A)),

              // ── Results table ───────────────────────────────────────────
              Expanded(
                flex: 3,
                child: _ResultsTable(results: results),
              ),

              const Divider(height: 1, color: Color(0xFF3A3A3A)),

              // ── FTP download status ─────────────────────────────────────
              Expanded(
                flex: 1,
                child: _FtpStatusPanel(ftpStatus: appState.tsyncFtpStatus),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Title bar ─────────────────────────────────────────────────────────────────

class _TitleBar extends StatelessWidget {
  final AppState appState;
  const _TitleBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF2D2D2D),
      child: Row(
        children: [
          const Icon(Icons.sync, size: 16, color: Colors.cyan),
          const SizedBox(width: 6),
          const Text(
            'T-Sync Acquisition',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          if (appState.tsyncRunning)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyan),
            ),
          const SizedBox(width: 8),
          // Clear button
          InkWell(
            onTap: appState.tsyncResults.isNotEmpty ? appState.tsyncClearResults : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[700]!),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status summary ────────────────────────────────────────────────────────────

class _StatusSummary extends StatelessWidget {
  final TsyncIterResult? latest;
  final AppState appState;
  const _StatusSummary({required this.latest, required this.appState});

  @override
  Widget build(BuildContext context) {
    if (latest == null) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        child: Text(
          appState.tsyncInitialized
              ? 'Waiting for acquisition...'
              : 'Not initialized. Press [acqinit] to start.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    final r = latest!;
    return Container(
      color: const Color(0xFF252525),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _StatusChip(label: 'Lock',    value: r.lockName,    ok: r.isLocked),
          const SizedBox(width: 12),
          _StatusChip(label: 'SSB',     value: r.ssbLockName, ok: r.ssbLock == Protocol.lockLocked || r.ssbLock == Protocol.lockHoldover),
          const SizedBox(width: 12),
          _StatusChip(label: 'State',   value: r.stateName,   ok: r.state >= 4),
          const SizedBox(width: 12),
          _StatusChip(label: 'CRC', value: r.crcOk ? 'OK' : 'FAIL', ok: r.crcOk),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;
  const _StatusChip({required this.label, required this.value, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green[400]! : Colors.red[400]!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            border: Border.all(color: color, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(value, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ── Results table ─────────────────────────────────────────────────────────────

// flex widths: timestamp=3, others=1
const _colHeaders = ['Timestamp', 'Iter', 'State', 'Lock', 'SSB', 'PCI', 'Beam', 'CRC', 'Corr', 'DAC'];
const _colFlex    = [          3,      1,       1,      1,     1,     1,      1,     1,      1,     1];

class _ResultsTable extends StatefulWidget {
  final List<TsyncIterResult> results;
  const _ResultsTable({required this.results});

  @override
  State<_ResultsTable> createState() => _ResultsTableState();
}

class _ResultsTableState extends State<_ResultsTable> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_ResultsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when new results arrive
    if (widget.results.length != oldWidget.results.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          color: const Color(0xFF2A2A2A),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: List.generate(_colHeaders.length, (i) => Expanded(
              flex: _colFlex[i],
              child: Text(_colHeaders[i],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w600)),
            )),
          ),
        ),
        // Rows
        Expanded(
          child: widget.results.isEmpty
              ? Center(
                  child: Text('No data', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: widget.results.length,
                  itemBuilder: (context, i) {
                    final r = widget.results[i];
                    final isEven = i % 2 == 0;
                    return _ResultRow(result: r, isEven: isEven);
                  },
                ),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final TsyncIterResult result;
  final bool isEven;
  const _ResultRow({required this.result, required this.isEven});

  @override
  Widget build(BuildContext context) {
    final r = result;
    final lockColor = r.isLocked ? Colors.green[400]! : Colors.red[400]!;
    final crcColor  = r.crcOk   ? Colors.green[400]! : Colors.red[400]!;

    final ts = r.timestamp;
    final tsStr =
        '${ts.year.toString().padLeft(4, '0')}-'
        '${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}.'
        '${ts.millisecond.toString().padLeft(3, '0')}';

    return Container(
      color: isEven ? const Color(0xFF222222) : const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _cell(tsStr, flex: 3),
          _cell('${r.iter}'),
          _cell(r.stateName, color: _stateColor(r.state)),
          _cell(r.lockName,    color: lockColor),
          _cell(r.ssbLockName, color: lockColor),
          _cell(r.pci == -1 ? '-' : '${r.pci}'),
          _cell('${r.beam}'),
          _cell(r.crcOk ? 'OK' : 'FAIL', color: crcColor),
          _cell('${r.corr}'),
          _cell('${r.curDac}'),
        ],
      ),
    );
  }

  Widget _cell(String text, {Color? color, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: color ?? Colors.white60),
      ),
    );
  }

  Color _stateColor(int state) {
    if (state >= 5) return Colors.green[400]!;
    if (state == 4) return Colors.lightGreen[400]!;
    if (state == 3) return Colors.yellow[600]!;
    return Colors.grey[500]!;
  }
}

// ── FTP status panel ──────────────────────────────────────────────────────────

class _FtpStatusPanel extends StatelessWidget {
  final Map<int, TsyncFtpStatus> ftpStatus;
  const _FtpStatusPanel({required this.ftpStatus});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFF2A2A2A),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: const Text(
            'IQ File Download',
            style: TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ftpStatus.isEmpty
              ? Center(
                  child: Text('No files downloaded',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  children: ftpStatus.entries.map((e) {
                    final s = e.value;
                    final counterStr = s.fileCounter.toString().padLeft(4, '0');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text('#$counterStr  ', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                          _ftpIcon('ACQ_I_$counterStr.txt', s.iDownloaded),
                          const SizedBox(width: 10),
                          _ftpIcon('ACQ_Q_$counterStr.txt', s.qDownloaded),
                          if (s.csvSaved) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.table_chart, size: 13, color: Colors.cyan),
                            const Text(' CSV', style: TextStyle(fontSize: 10, color: Colors.cyan)),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _ftpIcon(String filename, bool done) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle_outline : Icons.downloading,
          size: 13,
          color: done ? Colors.green[400] : Colors.yellow[600],
        ),
        const SizedBox(width: 3),
        Text(filename, style: TextStyle(fontSize: 10, color: done ? Colors.white54 : Colors.yellow[700])),
      ],
    );
  }
}
