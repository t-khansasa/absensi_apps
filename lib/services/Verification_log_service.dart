// verification_log_service.dart
//
// Tujuan: mencatat hasil tiap percobaan face recognition + liveness
// ke file CSV LOKAL di HP masing-masing user (bukan ke server/terminal).
// Nanti file ini di-export manual (share ke email/WA) untuk dikumpulkan
// jadi bahan analisis di BAB IV.
//
// Tambahkan dulu ke pubspec.yaml:
//   path_provider: ^2.1.1
//   csv: ^6.0.0
//   share_plus: ^7.2.1   (untuk fitur export/share file)

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

class FaceVerificationLog {
  final String tenantId;
  final String userId;
  final double similarityScore;
  final double thresholdUsed;
  final bool livenessPassed;
  final int processingTimeMs;
  final String deviceModel;
  final DateTime timestamp;

  FaceVerificationLog({
    required this.tenantId,
    required this.userId,
    required this.similarityScore,
    required this.thresholdUsed,
    required this.livenessPassed,
    required this.processingTimeMs,
    required this.deviceModel,
    required this.timestamp,
  });

  List<dynamic> toRow() => [
        tenantId,
        userId,
        similarityScore,
        thresholdUsed,
        livenessPassed,
        processingTimeMs,
        deviceModel,
        timestamp.toIso8601String(),
      ];
}

class VerificationLogService {
  static const _fileName = 'face_verification_log.csv';
  static const _header = [
    'tenant_id',
    'user_id',
    'similarity_score',
    'threshold_used',
    'liveness_passed',
    'processing_time_ms',
    'device_model',
    'timestamp',
  ];

  // Ambil path file log di penyimpanan aplikasi (aman, tidak perlu izin storage khusus)
  Future<File> _getLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');

    // Kalau file belum ada, buat dengan header dulu
    if (!await file.exists()) {
      final headerCsv = const ListToCsvConverter().convert([_header]);
      await file.writeAsString('$headerCsv\n');
    }
    return file;
  }

  // Panggil fungsi ini setiap kali proses verifikasi wajah selesai
  Future<void> logVerification(FaceVerificationLog log) async {
    try {
      final file = await _getLogFile();
      final rowCsv = const ListToCsvConverter().convert([log.toRow()]);
      await file.writeAsString('$rowCsv\n', mode: FileMode.append);
    } catch (e) {
      // Jangan sampai gagal logging mengganggu proses presensi utama
      debugPrintSafe('Gagal menyimpan log verifikasi: $e');
    }
  }

  // Panggil ini dari tombol tersembunyi (misal long-press logo di halaman profil)
  // untuk share file CSV ke email/WA/Drive, supaya kamu bisa kumpulkan dari tiap HP
  Future<void> exportLog() async {
    final file = await _getLogFile();
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Log pengujian face recognition - export untuk skripsi',
    );
  }

  // Opsional: hapus log setelah berhasil di-export, biar file tidak menumpuk
  Future<void> clearLog() async {
    final file = await _getLogFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  void debugPrintSafe(String message) {
    // ignore: avoid_print
    print(message);
  }
}

/* ============================================================
CONTOH PEMAKAIAN di modul face recognition kamu:

final logService = VerificationLogService();

// ...setelah proses hitung similarity & liveness selesai:
await logService.logVerification(
  FaceVerificationLog(
    tenantId: currentTenantId,
    userId: currentUserId,
    similarityScore: similarityResult,
    thresholdUsed: 0.35,
    livenessPassed: isLivenessPassed,
    processingTimeMs: stopwatch.elapsedMilliseconds,
    deviceModel: androidInfo.model, // dari device_info_plus
    timestamp: DateTime.now(),
  ),
);

// Contoh tombol export tersembunyi (misal di halaman profil, long-press logo):
GestureDetector(
  onLongPress: () => logService.exportLog(),
  child: Image.asset('assets/logo.png'),
)
============================================================ */