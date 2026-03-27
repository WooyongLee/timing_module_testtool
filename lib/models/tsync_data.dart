import '../constants/protocol.dart';

/// Per-iteration result from ACQ_RUN / ACQ_LOOP response (0x45 0x62)
/// Format: 0x45 0x62 <iter> <total> <lock> <ssb_lock> <state>
///          <pci> <beam> <crc> <corr> <cur_dac>
///          <file_saved> <file_counter>
class TsyncIterResult {
  final int iter;
  final int total;
  final int lock;
  final int ssbLock;
  final int state;
  final int pci;
  final int beam;
  final int crc;
  final int corr;
  final int curDac;
  final int fileSaved;
  final int fileCounter;
  final DateTime timestamp;

  TsyncIterResult({
    required this.iter,
    required this.total,
    required this.lock,
    required this.ssbLock,
    required this.state,
    required this.pci,
    required this.beam,
    required this.crc,
    required this.corr,
    required this.curDac,
    required this.fileSaved,
    required this.fileCounter,
  }) : timestamp = DateTime.now();

  /// Parse from ACQ_RUN completion response.
  /// Format: 0x45 0x62 1 <state> <lock> <pci> <beam> <crc> [corr] [curDac] [fileSaved] [fileCounter]
  /// tokens[2]="1", tokens[3]=state, tokens[4]=lock, tokens[5]=pci, tokens[6]=beam, tokens[7]=crc
  static TsyncIterResult? fromRunTokens(List<String> tokens) {
    if (tokens.length < 8) return null;
    try {
      return TsyncIterResult(
        iter:        1,
        total:       1,
        state:       int.parse(tokens[3]),
        lock:        int.parse(tokens[4]),
        ssbLock:     0,
        pci:         int.parse(tokens[5]),
        beam:        int.parse(tokens[6]),
        crc:         int.parse(tokens[7]),
        corr:        tokens.length > 8  ? (int.tryParse(tokens[8])  ?? 0) : 0,
        curDac:      tokens.length > 9  ? (int.tryParse(tokens[9])  ?? 0) : 0,
        fileSaved:   tokens.length > 10 ? (int.tryParse(tokens[10]) ?? 0) : 0,
        fileCounter: tokens.length > 11 ? (int.tryParse(tokens[11]) ?? 0) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse from ACQ_LOOP per-iteration response.
  /// Format: 0x45 0x65 1 <iter> <state> <lock> <pci> <beam> <crc> [corr] [curDac] [fileSaved] [fileCounter]
  /// tokens[2]="1", tokens[3]=iter, tokens[4]=state, tokens[5]=lock, tokens[6]=pci, tokens[7]=beam, tokens[8]=crc
  static TsyncIterResult? fromLoopTokens(List<String> tokens) {
    if (tokens.length < 9) return null;
    try {
      return TsyncIterResult(
        iter:        int.parse(tokens[3]),
        total:       0,
        state:       int.parse(tokens[4]),
        lock:        int.parse(tokens[5]),
        ssbLock:     0,
        pci:         int.parse(tokens[6]),
        beam:        int.parse(tokens[7]),
        crc:         int.parse(tokens[8]),
        corr:        tokens.length > 9  ? (int.tryParse(tokens[9])  ?? 0) : 0,
        curDac:      tokens.length > 10 ? (int.tryParse(tokens[10]) ?? 0) : 0,
        fileSaved:   tokens.length > 11 ? (int.tryParse(tokens[11]) ?? 0) : 0,
        fileCounter: tokens.length > 12 ? (int.tryParse(tokens[12]) ?? 0) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Legacy parser — rich format with 12 data fields (tokens[2..13]).
  /// Kept for backward compatibility if firmware sends extended format.
  static TsyncIterResult? fromTokens(List<String> tokens) {
    if (tokens.length < 14) return null;
    try {
      return TsyncIterResult(
        iter:        int.parse(tokens[2]),
        total:       int.parse(tokens[3]),
        lock:        int.parse(tokens[4]),
        ssbLock:     int.parse(tokens[5]),
        state:       int.parse(tokens[6]),
        pci:         int.parse(tokens[7]),
        beam:        int.parse(tokens[8]),
        crc:         int.parse(tokens[9]),
        corr:        int.parse(tokens[10]),
        curDac:      int.parse(tokens[11]),
        fileSaved:   int.parse(tokens[12]),
        fileCounter: int.parse(tokens[13]),
      );
    } catch (_) {
      return null;
    }
  }

  String get lockName  => Protocol.acqLockNames[lock]  ?? 'UNKNOWN';
  String get ssbLockName => Protocol.acqLockNames[ssbLock] ?? 'UNKNOWN';
  String get stateName => Protocol.acqStateNames[state] ?? 'UNKNOWN';
  bool   get isLocked  => lock == Protocol.lockLocked || lock == Protocol.lockHoldover;
  bool   get crcOk     => crc == 1;

  @override
  String toString() =>
      'TsyncIterResult(iter=$iter, lock=$lockName, state=$stateName, pci=$pci, beam=$beam, crc=$crc)';
}

/// ACQ_STATUS response (0x45 0x63)
/// Format: 0x45 0x63 <init> <lock> <ssb_lock> <pd_lock> <state>
class TsyncStatus {
  final int init;
  final int lock;
  final int ssbLock;
  final int pdLock;
  final int state;

  const TsyncStatus({
    required this.init,
    required this.lock,
    required this.ssbLock,
    required this.pdLock,
    required this.state,
  });

  static TsyncStatus? fromTokens(List<String> tokens) {
    if (tokens.length < 7) return null;
    try {
      return TsyncStatus(
        init:    int.parse(tokens[2]),
        lock:    int.parse(tokens[3]),
        ssbLock: int.parse(tokens[4]),
        pdLock:  int.parse(tokens[5]),
        state:   int.parse(tokens[6]),
      );
    } catch (_) {
      return null;
    }
  }

  String get lockName    => Protocol.acqLockNames[lock]    ?? 'UNKNOWN';
  String get ssbLockName => Protocol.acqLockNames[ssbLock] ?? 'UNKNOWN';
  String get stateName   => Protocol.acqStateNames[state]  ?? 'UNKNOWN';
  bool   get isLocked    => lock == Protocol.lockLocked || lock == Protocol.lockHoldover;
}

/// ACQ_RESULT detailed response (0x45 0x64) — 18 fields
/// Format: 0x45 0x64 <lock> <ssb_lock> <ssb_var1> <ssb_var2>
///          <pd_lock> <pd_var1> <pd_var2>
///          <dac_val> <cur_dac_val>
///          <cid> <beam_idx> <crc> <corr> <index_diff>
///          <p_pwr> <s_pwr> <pss_evm> <sss_sinr>
/// Power/EVM/SINR unit: 1/100 (e.g. -9000 → -90.00)
class TsyncAcqResult {
  final int lock;
  final int ssbLock;
  final int ssbVar1;
  final int ssbVar2;
  final int pdLock;
  final int pdVar1;
  final int pdVar2;
  final int dacVal;
  final int curDacVal;
  final int cid;
  final int beamIdx;
  final int crc;
  final int corr;
  final int indexDiff;
  final double pPwr;
  final double sPwr;
  final double pssEvm;
  final double sssSinr;

  const TsyncAcqResult({
    required this.lock,
    required this.ssbLock,
    required this.ssbVar1,
    required this.ssbVar2,
    required this.pdLock,
    required this.pdVar1,
    required this.pdVar2,
    required this.dacVal,
    required this.curDacVal,
    required this.cid,
    required this.beamIdx,
    required this.crc,
    required this.corr,
    required this.indexDiff,
    required this.pPwr,
    required this.sPwr,
    required this.pssEvm,
    required this.sssSinr,
  });

  static TsyncAcqResult? fromTokens(List<String> tokens) {
    if (tokens.length < 20) return null;
    try {
      return TsyncAcqResult(
        lock:       int.parse(tokens[2]),
        ssbLock:    int.parse(tokens[3]),
        ssbVar1:    int.parse(tokens[4]),
        ssbVar2:    int.parse(tokens[5]),
        pdLock:     int.parse(tokens[6]),
        pdVar1:     int.parse(tokens[7]),
        pdVar2:     int.parse(tokens[8]),
        dacVal:     int.parse(tokens[9]),
        curDacVal:  int.parse(tokens[10]),
        cid:        int.parse(tokens[11]),
        beamIdx:    int.parse(tokens[12]),
        crc:        int.parse(tokens[13]),
        corr:       int.parse(tokens[14]),
        indexDiff:  int.parse(tokens[15]),
        pPwr:       int.parse(tokens[16]) / 100.0,
        sPwr:       int.parse(tokens[17]) / 100.0,
        pssEvm:     int.parse(tokens[18]) / 100.0,
        sssSinr:    int.parse(tokens[19]) / 100.0,
      );
    } catch (_) {
      return null;
    }
  }

  String get lockName => Protocol.acqLockNames[lock] ?? 'UNKNOWN';
  bool   get crcOk    => crc == 1;
}

/// FTP download status for a single file counter
class TsyncFtpStatus {
  final int fileCounter;
  bool iDownloaded;
  bool qDownloaded;
  bool csvSaved;

  TsyncFtpStatus({
    required this.fileCounter,
    this.iDownloaded = false,
    this.qDownloaded = false,
    this.csvSaved    = false,
  });

  bool get bothDownloaded => iDownloaded && qDownloaded;
}
