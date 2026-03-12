import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';

void showRegisterWindow(BuildContext context, MqttService mqtt) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => RegisterWindow(mqtt: mqtt),
  );
}

class RegisterWindow extends StatefulWidget {
  final MqttService mqtt;
  const RegisterWindow({super.key, required this.mqtt});

  @override
  State<RegisterWindow> createState() => _RegisterWindowState();
}

class _RegisterWindowState extends State<RegisterWindow>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<RegisterResponse>? _subscription;

  // Response display map: subCommand -> raw response string
  final Map<int, String> _responses = {};

  // Auto-fill controllers keyed by "subcmd_paramName"
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _subscription = widget.mqtt.registerResponseStream.listen(_onRegisterResponse);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _tabController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key, [String initial = '']) {
    return _controllers.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  void _onRegisterResponse(RegisterResponse resp) {
    setState(() {
      _responses[resp.subCommand] = resp.rawResponse;
    });
    _autoFill(resp);
  }

  void _autoFill(RegisterResponse resp) {
    final p = resp.params;
    switch (resp.subCommand) {
      case 0x10:
        // Timing status: 25 values (cnt1_period, tsync_offset, tsync_period, mtsync_offset,
        // tsync_off, mtsync_off, mux_ctrl, sig0_on..sig7_off)
        final labels = _timingStatusLabels;
        for (int i = 0; i < labels.length && i < p.length; i++) {
          _ctrl('0x10_${labels[i]}').text = p[i];
        }
        break;
      case 0x20:
        // Corr status: 9 values
        final labels = _corrStatusLabels;
        for (int i = 0; i < labels.length && i < p.length; i++) {
          _ctrl('0x20_${labels[i]}').text = p[i];
        }
        break;
      case 0x30:
        // FIR status
        if (p.isNotEmpty) _ctrl('0x30_fir_ctrl_raw').text = p[0];
        break;
      case 0x41:
        // Freq translation status
        if (p.isNotEmpty) _ctrl('0x41_freq_mhz_x1000').text = p[0];
        if (p.length > 1) _ctrl('0x41_bypass').text = p[1];
        break;
      case 0x46:
        // Power meas status
        final labels = ['ready', 'fullness', 'capt_done'];
        for (int i = 0; i < labels.length && i < p.length; i++) {
          _ctrl('0x46_${labels[i]}').text = p[i];
        }
        break;
    }
    if (mounted) setState(() {});
  }

  void _sendCmd(int subCmd, [List<String>? params]) {
    final parts = ['0x44', '0x${subCmd.toRadixString(16).padLeft(2, '0')}'];
    if (params != null) parts.addAll(params);
    widget.mqtt.sendCommand(parts.join(' '));
  }

  static const _timingStatusLabels = [
    'cnt1_period',
    'tsync_offset',
    'tsync_period',
    'mtsync_offset',
    'tsync_off',
    'mtsync_off',
    'mux_ctrl',
    'sig0_on', 'sig0_off',
    'sig1_on', 'sig1_off',
    'sig2_on', 'sig2_off',
    'sig3_on', 'sig3_off',
    'sig4_on', 'sig4_off',
    'sig5_on', 'sig5_off',
    'sig6_on', 'sig6_off',
    'sig7_on', 'sig7_off',
  ];

  static const _corrStatusLabels = [
    'tcb_rdy',
    'tcb_det_num',
    'fcb_rdy',
    'fcb_det_num',
    'xfft_status',
    'corr_ctrl',
    'tcb_ths',
    'fcb_ths',
    'tcb_offset',
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 820,
        height: 620,
        child: Column(
          children: [
            // Title bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.teal[700],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.memory, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Register Control',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Tab bar
            Container(
              color: Colors.teal[50],
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.teal[800],
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.teal[700],
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Timing'),
                  Tab(text: 'Correlation'),
                  Tab(text: 'FIR'),
                  Tab(text: 'FPGA Control'),
                ],
              ),
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTimingTab(),
                  _buildCorrelationTab(),
                  _buildFirTab(),
                  _buildFpgaTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  //  REUSABLE BUILDERS
  // ──────────────────────────────────────────────────────

  Widget _card({
    required String title,
    required int subCmd,
    List<_ParamDef>? params,
    bool getOnly = false,
    bool setOnly = false,
    VoidCallback? onGet,
    VoidCallback? onSet,
    Widget? extra,
  }) {
    final hexStr = '0x${subCmd.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    hexStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800],
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (!setOnly)
                  _actionBtn('Get', Colors.blue, onGet ?? () => _sendCmd(subCmd)),
                if (!getOnly && !setOnly) const SizedBox(width: 4),
                if (!getOnly)
                  _actionBtn(
                    'Set',
                    Colors.orange,
                    onSet ??
                        () {
                          if (params != null) {
                            final vals = params
                                .map((p) => _ctrl('0x${subCmd.toRadixString(16)}_${p.name}').text)
                                .toList();
                            _sendCmd(subCmd, vals);
                          } else {
                            _sendCmd(subCmd);
                          }
                        },
                  ),
              ],
            ),
            // Params
            if (params != null && params.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: params.map((p) {
                  return _input(
                    label: p.label,
                    key: '0x${subCmd.toRadixString(16)}_${p.name}',
                    hint: p.hint,
                    width: p.width,
                  );
                }).toList(),
              ),
            ],
            if (extra != null) ...[
              const SizedBox(height: 6),
              extra,
            ],
            // Response display
            if (_responses.containsKey(subCmd)) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SelectableText(
                  _responses[subCmd]!,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _input({
    required String label,
    required String key,
    String? hint,
    double width = 100,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          SizedBox(
            height: 26,
            child: TextField(
              controller: _ctrl(key),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(3)),
                filled: true,
                fillColor: Colors.white,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      height: 24,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _statusCard({
    required String title,
    required int subCmd,
    required List<String> labels,
  }) {
    final hexKey = '0x${subCmd.toRadixString(16)}';
    return _card(
      title: title,
      subCmd: subCmd,
      getOnly: true,
      extra: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: labels.map((l) {
          return SizedBox(
            width: 110,
            child: Row(
              children: [
                Expanded(
                  child: Text(l, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ),
                SizedBox(
                  width: 60,
                  height: 22,
                  child: TextField(
                    controller: _ctrl('${hexKey}_$l'),
                    readOnly: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(3)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  //  TIMING TAB (0x10-0x19)
  // ──────────────────────────────────────────────────────

  Widget _buildTimingTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _statusCard(
          title: 'Get Timing Status',
          subCmd: 0x10,
          labels: _timingStatusLabels,
        ),
        _card(
          title: 'Set CNT1 Period',
          subCmd: 0x11,
          getOnly: false,
          setOnly: true,
          params: [_ParamDef('period', 'period')],
        ),
        _card(
          title: 'Set TSYNC',
          subCmd: 0x12,
          setOnly: true,
          params: [
            _ParamDef('offset', 'offset'),
            _ParamDef('period', 'period'),
            _ParamDef('off', 'off'),
          ],
        ),
        _card(
          title: 'Set MTSYNC',
          subCmd: 0x13,
          setOnly: true,
          params: [
            _ParamDef('offset', 'offset'),
            _ParamDef('off', 'off'),
          ],
        ),
        _card(
          title: 'Set Signal Timing',
          subCmd: 0x14,
          setOnly: true,
          params: [
            _ParamDef('sig_num', 'sig# (0-7)', width: 80),
            _ParamDef('on_time', 'on_time'),
            _ParamDef('off_time', 'off_time'),
          ],
        ),
        _card(
          title: 'Set Signal Timing NS',
          subCmd: 0x15,
          setOnly: true,
          params: [
            _ParamDef('sig_num', 'sig# (0-7)', width: 80),
            _ParamDef('on_ns', 'on_ns'),
            _ParamDef('off_ns', 'off_ns'),
            _ParamDef('on_offset', 'on_offset'),
            _ParamDef('off_offset', 'off_offset'),
          ],
        ),
        _card(
          title: 'Set MUX Control',
          subCmd: 0x16,
          setOnly: true,
          params: [_ParamDef('mux_value', 'mux_value')],
        ),
        _card(
          title: 'Set MUX Signal',
          subCmd: 0x17,
          setOnly: true,
          params: [
            _ParamDef('sig_type', 'sig_type', hint: '0-9', width: 80),
            _ParamDef('ctrl', 'ctrl', hint: '0-3', width: 80),
          ],
          extra: const Text(
            'sig_type: 0=TSYNC 1=MTSYNC 2-9=SIG0~7\nctrl: 0=normal 1=inv 2=low 3=high',
            style: TextStyle(fontSize: 9, color: Colors.black45),
          ),
        ),
        _card(
          title: 'Configure TDD',
          subCmd: 0x18,
          setOnly: true,
          params: [
            _ParamDef('dl_interval', 'DL interval'),
            _ParamDef('ul_interval', 'UL interval'),
            _ParamDef('guard_interval', 'Guard interval'),
            _ParamDef('tsync_delay', 'TSYNC delay'),
          ],
        ),
        _card(
          title: 'Set ICS Preset',
          subCmd: 0x19,
          setOnly: true,
          params: [_ParamDef('preset', 'preset')],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  //  CORRELATION TAB (0x20-0x2B)
  // ──────────────────────────────────────────────────────

  Widget _buildCorrelationTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _statusCard(
          title: 'Get Corr Status',
          subCmd: 0x20,
          labels: _corrStatusLabels,
        ),
        _card(
          title: 'Set Corr Reset',
          subCmd: 0x21,
          setOnly: true,
          params: [_ParamDef('reset', 'reset', hint: '0/1', width: 80)],
        ),
        _card(
          title: 'Set Corr Control',
          subCmd: 0x22,
          setOnly: true,
          params: [
            _ParamDef('deci_rate', 'deci_rate'),
            _ParamDef('en_invert', 'en_invert', width: 80),
            _ParamDef('coef_sel', 'coef_sel', width: 80),
            _ParamDef('sample_offset', 'sample_offset'),
          ],
        ),
        _card(
          title: 'Set Corr Threshold',
          subCmd: 0x23,
          setOnly: true,
          params: [
            _ParamDef('tcb_ths', 'tcb_ths'),
            _ParamDef('fcb_ths', 'fcb_ths'),
          ],
        ),
        _card(
          title: 'Set TCB Offset',
          subCmd: 0x24,
          setOnly: true,
          params: [_ParamDef('offset', 'offset')],
        ),
        _card(
          title: 'Get TCB Positions',
          subCmd: 0x25,
          getOnly: true,
        ),
        _card(
          title: 'Get TCB Data',
          subCmd: 0x26,
          getOnly: true,
        ),
        _card(
          title: 'TCB Wait',
          subCmd: 0x27,
          setOnly: true,
          params: [_ParamDef('timeout_ms', 'timeout (ms)')],
        ),
        _card(
          title: 'Get FCB Status',
          subCmd: 0x28,
          getOnly: true,
          extra: _responses.containsKey(0x28)
              ? Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: ['fifo_init', 'buf_wcnt', 'fifo_full', 'fifo_empty', 'fifo_rdcnt', 'capt_rdy', 'capt_done']
                      .map((l) => SizedBox(
                            width: 110,
                            child: Row(
                              children: [
                                Expanded(child: Text(l, style: const TextStyle(fontSize: 10, color: Colors.black54))),
                                SizedBox(
                                  width: 50,
                                  height: 22,
                                  child: TextField(
                                    controller: _ctrl('0x28_$l'),
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(3)),
                                      filled: true,
                                      fillColor: Colors.grey[50],
                                    ),
                                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                )
              : null,
        ),
        _card(
          title: 'Set FCB DMA',
          subCmd: 0x29,
          setOnly: true,
          params: [
            _ParamDef('dma_length', 'dma_length'),
            _ParamDef('set_done', 'set_done', width: 80),
          ],
        ),
        _card(
          title: 'FCB Wait',
          subCmd: 0x2A,
          setOnly: true,
          params: [_ParamDef('timeout_ms', 'timeout (ms)')],
        ),
        _card(
          title: 'Get XFFT Status',
          subCmd: 0x2B,
          getOnly: true,
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  //  FIR TAB (0x30-0x34)
  // ──────────────────────────────────────────────────────

  Widget _buildFirTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _statusCard(
          title: 'Get FIR Status',
          subCmd: 0x30,
          labels: ['fir_ctrl_raw'],
        ),
        _card(
          title: 'Set FIR1 Params',
          subCmd: 0x31,
          setOnly: true,
          params: [
            _ParamDef('coef_sel', 'coef_sel', hint: '0-2', width: 80),
            _ParamDef('scale', 'scale', hint: '0-3', width: 80),
          ],
          extra: const Text(
            'scale: 0=[30:15] 1=[29:14] 2=[28:13] 3=[27:12]',
            style: TextStyle(fontSize: 9, color: Colors.black45),
          ),
        ),
        _card(
          title: 'Set FIR2 Params',
          subCmd: 0x32,
          setOnly: true,
          params: [
            _ParamDef('coef_sel', 'coef_sel', hint: '0-8', width: 80),
            _ParamDef('scale', 'scale', hint: '0-3', width: 80),
          ],
          extra: const Text(
            'scale: 0=[30:15] 1=[29:14] 2=[28:13] 3=[27:12]',
            style: TextStyle(fontSize: 9, color: Colors.black45),
          ),
        ),
        _card(
          title: 'FIR1 Reload',
          subCmd: 0x33,
          setOnly: true,
          params: [_ParamDef('coef_sel', 'coef_sel', width: 80)],
        ),
        _card(
          title: 'FIR2 Reload',
          subCmd: 0x34,
          setOnly: true,
          params: [_ParamDef('coef_sel', 'coef_sel', width: 80)],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  //  FPGA CONTROL TAB (0x40-0x4F)
  // ──────────────────────────────────────────────────────

  Widget _buildFpgaTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _card(
          title: 'Set Freq Translation',
          subCmd: 0x40,
          setOnly: true,
          params: [_ParamDef('freq_mhz_x1000', 'freq (milli-MHz)', width: 140)],
          extra: const Text(
            'e.g. 1500 = 1.5 MHz, -1500 = -1.5 MHz',
            style: TextStyle(fontSize: 9, color: Colors.black45),
          ),
        ),
        _statusCard(
          title: 'Get Freq Translation',
          subCmd: 0x41,
          labels: ['freq_mhz_x1000', 'bypass'],
        ),
        _card(
          title: 'Set FT Bypass',
          subCmd: 0x42,
          setOnly: true,
          params: [_ParamDef('bypass', 'bypass', hint: '0/1', width: 80)],
        ),
        _card(
          title: 'Set FIR Bypass',
          subCmd: 0x43,
          setOnly: true,
          params: [_ParamDef('bypass', 'bypass', hint: '0/1', width: 80)],
        ),
        _card(
          title: 'FIR Reload Coef',
          subCmd: 0x44,
          setOnly: true,
          params: [_ParamDef('coef_sel', 'coef_sel', width: 80)],
        ),
        _card(
          title: 'Set CNT1 Offset',
          subCmd: 0x45,
          setOnly: true,
          params: [
            _ParamDef('mode', 'mode', hint: '0-2', width: 80),
            _ParamDef('offset', 'offset'),
          ],
          extra: const Text(
            'mode: 0=disable 1=enable+set 2=trigger',
            style: TextStyle(fontSize: 9, color: Colors.black45),
          ),
        ),
        _statusCard(
          title: 'Get Power Meas Status',
          subCmd: 0x46,
          labels: ['ready', 'fullness', 'capt_done'],
        ),
        _card(
          title: 'Set Power Meas DMA',
          subCmd: 0x47,
          setOnly: true,
          params: [
            _ParamDef('length_words', 'length_words'),
            _ParamDef('set_done', 'set_done', width: 80),
          ],
        ),
        _card(
          title: 'Read Register',
          subCmd: 0x48,
          getOnly: true,
          params: [_ParamDef('reg_offset', 'reg_offset', hint: 'hex', width: 120)],
          onGet: () {
            final offset = _ctrl('0x48_reg_offset').text;
            _sendCmd(0x48, [offset]);
          },
        ),
        _card(
          title: 'Write Register',
          subCmd: 0x49,
          setOnly: true,
          params: [
            _ParamDef('reg_offset', 'reg_offset', hint: 'hex', width: 120),
            _ParamDef('value', 'value', hint: 'hex', width: 120),
          ],
        ),
        _card(
          title: 'Read DMA Register',
          subCmd: 0x4A,
          getOnly: true,
          params: [_ParamDef('reg_offset', 'reg_offset', hint: 'hex', width: 120)],
          onGet: () {
            final offset = _ctrl('0x4a_reg_offset').text;
            _sendCmd(0x4A, [offset]);
          },
        ),
        _card(
          title: 'Write DMA Register',
          subCmd: 0x4B,
          setOnly: true,
          params: [
            _ParamDef('reg_offset', 'reg_offset', hint: 'hex', width: 120),
            _ParamDef('value', 'value', hint: 'hex', width: 120),
          ],
        ),
        _statusCard(
          title: 'Get FPGA Info',
          subCmd: 0x4C,
          labels: ['product_id', 'hw_ver', 'build', 'board_id'],
        ),
        _card(
          title: 'Register Dump',
          subCmd: 0x4D,
          setOnly: true,
          params: [
            _ParamDef('start_reg', 'start_reg', hint: 'hex', width: 120),
            _ParamDef('end_reg', 'end_reg', hint: 'hex', width: 120),
          ],
        ),
        _card(
          title: 'PWR DMA Transfer',
          subCmd: 0x4E,
          setOnly: true,
          params: [_ParamDef('length_words', 'length_words')],
        ),
        _card(
          title: 'PWR DMA Reset',
          subCmd: 0x4F,
          setOnly: true,
          onSet: () => _sendCmd(0x4F),
        ),
      ],
    );
  }
}

class _ParamDef {
  final String name;
  final String label;
  final String? hint;
  final double width;

  const _ParamDef(this.name, this.label, {this.hint, this.width = 100});
}
