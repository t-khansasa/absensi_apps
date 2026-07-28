// verification_log_service.dart (VERSI UPDATE)
//
// Perubahan dari versi sebelumnya:
// - Tambah field `scenario` (kondisi pengujian) dan `attemptNumber`
// - Semua tetap tersimpan dalam 1 file CSV, tidak perlu pencatatan terpisah
//
// pubspec.yaml yang dibutuhkan (sama seperti sebelumnya):
//   path_provider: ^2.1.5
//   csv: ^6.0.0
//   share_plus: ^7.2.2

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

// Daftar skenario pengujian yang tersedia untuk dipilih user
enum TestScenario {
  normal('normal'),
  cahayaRendah('cahaya_rendah'),
  cahayaTerlaluTerang('cahaya_terlalu_terang');

  final String label;
  const TestScenario(this.label);
}

class FaceVerificationLog {
  final String tenantId;
  final String userId;
  final String scenario;       // BARU
  final int attemptNumber;     // BARU
  final double similarityScore;
  final double thresholdUsed;
  final bool livenessPassed;
  final int processingTimeMs;
  final String deviceModel;
  final DateTime timestamp;

  FaceVerificationLog({
    required this.tenantId,
    required this.userId,
    required this.scenario,
    required this.attemptNumber,
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
        scenario,
        attemptNumber,
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
    'scenario',
    'attempt_number',
    'similarity_score',
    'threshold_used',
    'liveness_passed',
    'processing_time_ms',
    'device_model',
    'timestamp',
  ];

  Future<File> _getLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    if (!await file.exists()) {
      final headerCsv = const ListToCsvConverter().convert([_header]);
      await file.writeAsString('$headerCsv\n');
    }
    return file;
  }

  // Hitung otomatis attempt_number berikutnya untuk kombinasi
  // user + tenant + scenario tertentu, supaya user tidak perlu input manual
  Future<int> getNextAttemptNumber({
    required String tenantId,
    required String userId,
    required String scenario,
  }) async {
    final file = await _getLogFile();
    final content = await file.readAsString();
    final rows = const CsvToListConverter().convert(content);

    int count = 0;
    for (final row in rows.skip(1)) {
      if (row.length < 3) continue;
      if (row[0].toString() == tenantId &&
          row[1].toString() == userId &&
          row[2].toString() == scenario) {
        count++;
      }
    }
    return count + 1;
  }

  Future<void> logVerification(FaceVerificationLog log) async {
    try {
      final file = await _getLogFile();
      final rowCsv = const ListToCsvConverter().convert([log.toRow()]);
      await file.writeAsString('$rowCsv\n', mode: FileMode.append);
    } catch (e) {
      // ignore: avoid_print
      print('Gagal menyimpan log verifikasi: $e');
    }
  }

  Future<void> exportLog() async {
    final file = await _getLogFile();
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Log pengujian face recognition - export untuk skripsi',
    );
  }

  Future<void> clearLog() async {
    final file = await _getLogFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}