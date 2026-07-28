// scenario_picker_dialog.dart
//
// Dialog ini dipanggil SEBELUM proses face recognition dijalankan,
// khusus untuk sesi testing/pengujian skripsi.
// Hasil pilihan user akan dipakai untuk mengisi field `scenario` di log CSV.

import 'package:flutter/material.dart';
import 'verification_log_service.dart';

/// Menampilkan dialog pilihan kondisi pengujian.
/// Return null kalau user membatalkan (misal ingin presensi normal tanpa testing).
Future<TestScenario?> showScenarioPickerDialog(BuildContext context) async {
  return showDialog<TestScenario>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Pilih Kondisi Pengujian'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TestScenario.values.map((scenario) {
            return ListTile(
              title: Text(_labelFor(scenario)),
              onTap: () => Navigator.pop(context, scenario),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Batal (presensi biasa)'),
          ),
        ],
      );
    },
  );
}

String _labelFor(TestScenario scenario) {
  switch (scenario) {
    case TestScenario.normal:
      return 'Normal (cahaya cukup)';
    case TestScenario.cahayaRendah:
      return 'Cahaya Rendah (redup/gelap)';
    case TestScenario.cahayaTerlaluTerang:
      return 'Cahaya Terlalu Terang (backlight)';
  }
}

/* ============================================================
CONTOH PEMAKAIAN di halaman presensi (misalnya attendance_page.dart):

import 'scenario_picker_dialog.dart';
import 'verification_log_service.dart';

final logService = VerificationLogService();

// Panggil ini SEBELUM proses buka kamera/scan wajah:
Future<void> _startFaceRecognitionTesting() async {
  final scenario = await showScenarioPickerDialog(context);
  if (scenario == null) {
    // User pilih "batal" -> lanjut presensi biasa TANPA logging
    // (langsung panggil fungsi scan wajah normal kamu di sini)
    return;
  }

  // Hitung attempt_number otomatis untuk kombinasi user+tenant+scenario ini
  final attemptNumber = await logService.getNextAttemptNumber(
    tenantId: currentTenantId,
    userId: currentUserId,
    scenario: scenario.label,
  );

  // Jalankan proses scan wajah seperti biasa (kode existing kamu)
  final stopwatch = Stopwatch()..start();
  // ... proses face recognition & liveness detection kamu di sini ...
  // final similarityResult = ...
  // final isLivenessPassed = ...
  stopwatch.stop();

  // Simpan hasilnya ke log, sudah termasuk scenario & attempt_number
  await logService.logVerification(
    FaceVerificationLog(
      tenantId: currentTenantId,
      userId: currentUserId,
      scenario: scenario.label,
      attemptNumber: attemptNumber,
      similarityScore: similarityResult,
      thresholdUsed: 0.45, // sesuaikan dengan threshold yang sedang dipakai
      livenessPassed: isLivenessPassed,
      processingTimeMs: stopwatch.elapsedMilliseconds,
      deviceModel: androidInfo.model,
      timestamp: DateTime.now(),
    ),
  );
}
============================================================ */