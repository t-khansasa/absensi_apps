// scenario_picker_dialog.dart (VERSI UPDATE — 5 skenario)
//
// Dialog ini dipanggil SEBELUM proses face recognition dijalankan,
// khusus untuk sesi testing/pengujian skripsi.
// TestScenario didefinisikan di verification_log_service.dart, di-import dari sana
// supaya tidak ada definisi ganda.

import 'package:flutter/material.dart';
import 'verification_log_service.dart';

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
    case TestScenario.pakaiMasker:
      return 'Pakai Masker';
    case TestScenario.pakaiKacamata:
      return 'Pakai Kacamata';
  }
}