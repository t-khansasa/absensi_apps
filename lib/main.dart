import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart'; // 1. Tambahkan import ini
import 'screens/login_page.dart';

void main() async {
  // 2. Tambahkan dua baris ini agar aplikasi mendukung format tanggal Indonesia
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aplikasi Absensi',
      theme: ThemeData(
        primaryColor: const Color(0xFF1B5E20),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
          ),
        ),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
