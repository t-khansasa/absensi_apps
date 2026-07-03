import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import 'scan_screen.dart';

class AbsenPulangScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const AbsenPulangScreen({super.key, required this.userData});

  @override
  State<AbsenPulangScreen> createState() => _AbsenPulangScreenState();
}

class _AbsenPulangScreenState extends State<AbsenPulangScreen> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  bool _isSubmitting = false;
  String _locationMessage = 'Menunggu lokasi...';
  String _locationStatus = 'Belum terdeteksi';
  String? _checkinTime;
  String? _checkoutTime;
  String? _checkoutNote;
  String? _errorMessage;

  TimeOfDay _shiftEnd = const TimeOfDay(hour: 17, minute: 0);
  bool _isLoadingOffice = true;

  static const int _checkoutOffsetMinutes = 0;

  // ─── Warna tema ────────────────────────────────────────────────────────────
  static const Color _navyDark = Color(0xFF0A2246);
  static const Color _navyMid = Color(0xFF1D4461);
  static const Color _navyLight = Color(0xFF90CAF9);

  @override
  void initState() {
    super.initState();
    _startClock();
    _fetchOfficeSchedule();
    _loadAttendanceData();
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  // ─── Logic (tidak diubah) ──────────────────────────────────────────────────

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _fetchOfficeSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/offices'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> offices = body['data'] ?? [];

        if (offices.isNotEmpty) {
          final office = offices.first as Map<String, dynamic>;
          final checkOutTime = office['check_out_time']?.toString();

          if (checkOutTime != null && checkOutTime.isNotEmpty) {
            final parsed = _parseTimeString(checkOutTime);
            if (mounted) setState(() => _shiftEnd = parsed);
          }
        }
      }
    } catch (e) {
      debugPrint('Gagal fetch office schedule: $e');
    }

    if (mounted) setState(() => _isLoadingOffice = false);
  }

  TimeOfDay _parseTimeString(String value) {
    final cleaned = value.trim();
    final parts = cleaned.split(RegExp(r'[:.]'));
    if (parts.length < 2) return const TimeOfDay(hour: 17, minute: 0);
    final hour = int.tryParse(parts[0]) ?? 17;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String get _todayDateLabel =>
      DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_now);

  String get _todayTimeLabel => DateFormat('HH:mm:ss').format(_now);

  String _formatClockLabel(TimeOfDay time) => time.format(context);

  String get _shiftEndLabel => _formatClockLabel(_shiftEnd);

  DateTime get _todayShiftEnd => DateTime(
    _now.year,
    _now.month,
    _now.day,
    _shiftEnd.hour,
    _shiftEnd.minute,
  );

  DateTime get _checkoutAvailableAt =>
      _todayShiftEnd.subtract(Duration(minutes: _checkoutOffsetMinutes));

  bool get _isCheckoutAvailable =>
      _now.isAfter(_checkoutAvailableAt) ||
      _now.isAtSameMomentAs(_checkoutAvailableAt);

  String get _departmentLabel {
    final data = widget.userData;
    final dept = data['department'];
    if (dept is Map) return dept['name']?.toString() ?? 'Operasional';
    if (dept is String && dept.isNotEmpty) return dept;
    final position = data['position'];
    if (position is Map) return position['name']?.toString() ?? 'Operasional';
    if (position is String && position.isNotEmpty) return position;
    return 'Operasional';
  }

  Future<void> _loadAttendanceData() async {
    await _loadLocalCheckout();
    await _fetchAttendanceHistory();
  }

  Future<void> _loadLocalCheckout() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.userData['id']?.toString() ?? 'guest';
    final key =
        'absen_pulang_${userId}_${DateFormat('yyyy-MM-dd').format(_now)}';
    final stored = prefs.getString(key);
    if (stored == null) return;

    final map = jsonDecode(stored) as Map<String, dynamic>;
    if (mounted) {
      setState(() {
        _checkoutTime = map['checkoutTime']?.toString();
        _checkoutNote = map['checkoutNote']?.toString();
        _locationMessage =
            map['locationMessage']?.toString() ?? _locationMessage;
        _locationStatus = map['locationStatus']?.toString() ?? _locationStatus;
      });
    }
  }

  Future<void> _saveLocalCheckout(
    String checkoutTime,
    String locationMessage,
    String locationStatus,
    String note,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.userData['id']?.toString() ?? 'guest';
    final key =
        'absen_pulang_${userId}_${DateFormat('yyyy-MM-dd').format(_now)}';
    final payload = jsonEncode({
      'checkoutTime': checkoutTime,
      'locationMessage': locationMessage,
      'locationStatus': locationStatus,
      'checkoutNote': note,
    });
    await prefs.setString(key, payload);
  }

  Future<void> _fetchAttendanceHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final uri = Uri.parse('${AppConstants.baseUrl}/attendance');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> items = body['data'] ?? [];
        final todayKey = DateFormat('yyyy-MM-dd').format(_now);

        String? checkinTime;
        String? checkoutTime;
        String? checkoutNote;

        for (final item in items) {
          final row = item as Map<String, dynamic>;
          final date = row['date']?.toString() ?? '';
          if (date != todayKey) continue;

          checkinTime ??=
              row['time_in']?.toString() ?? row['jam_masuk']?.toString();
          checkoutTime =
              row['time_out']?.toString() ??
              row['jam_pulang']?.toString() ??
              checkoutTime;
          if (checkoutTime != null && row['location_out'] != null) {
            checkoutNote = 'GPS terdeteksi';
          }
        }

        if (mounted) {
          setState(() {
            _checkinTime = checkinTime;
            _checkoutTime = checkoutTime ?? _checkoutTime;
            _checkoutNote = checkoutNote ?? _checkoutNote;
          });
        }
      }
    } catch (e) {
      debugPrint('Gagal memuat riwayat absen: $e');
    }
  }

  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationMessage = 'GPS dimatikan');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      setState(() => _locationMessage = 'Izin lokasi ditolak');
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _handleCheckout() async {
    if (!_isCheckoutAvailable) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final position = await _determinePosition();
    if (position == null) {
      if (mounted) {
        setState(() {
          _locationStatus = 'Gagal';
          _isSubmitting = false;
          _errorMessage = 'Tidak bisa mengambil lokasi saat ini.';
        });
      }
      return;
    }

    const locationStatus = 'Terdeteksi';
    const locationMessage = 'GPS terdeteksi ✓';

    final checkoutTime = DateFormat('HH:mm').format(_now);
    final bool success =
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => const ScanScreen()),
        ) ??
        false;

    if (!success) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _locationStatus = locationStatus;
          _locationMessage = locationMessage;
        });
      }
      return;
    }

    await _saveLocalCheckout(
      checkoutTime,
      locationMessage,
      locationStatus,
      'Absen pulang tercatat.',
    );

    if (mounted) {
      setState(() {
        _checkoutTime = checkoutTime;
        _checkoutNote = 'GPS terdeteksi ✓';
        _locationStatus = locationStatus;
        _locationMessage = locationMessage;
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Absen pulang berhasil dikirim ke server.'),
        ),
      );
    }
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // ─── Build utama ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_navyDark, _navyMid, _navyLight],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── AppBar custom ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Card pill transparan di belakang judul, sama seperti
                    // pill "Riwayat Pengajuan" pada referensi gambar.
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                          ),
                        ),
                        child: const Text(
                          'Absen Pulang',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tanggal & jam ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _todayDateLabel,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _todayTimeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Konten scrollable ──────────────────────────────────────────
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _fetchOfficeSchedule();
                    await _loadAttendanceData();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Column(
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: 16),
                        _buildStatusCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Card Departemen & Jam Pulang ──────────────────────────────────────────

  Widget _buildHeaderCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Ikon departemen
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2340).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.business_center_outlined,
              color: _navyDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Departemen',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  _departmentLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _navyDark,
                  ),
                ),
              ],
            ),
          ),
          // Badge jam pulang
          _isLoadingOffice
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _navyDark,
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2340),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.white70,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _shiftEndLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  // ─── Card Status & Tombol Absen ────────────────────────────────────────────

  Widget _buildStatusCard() {
    final bool canTap = _isCheckoutAvailable && _checkoutTime == null;
    final remaining = _checkoutAvailableAt.difference(_now);
    final countdown = remaining.isNegative
        ? '00:00:00'
        : formatDuration(remaining);
    final alreadyDone = _checkoutTime != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status utama ─────────────────────────────────────────────────
          if (alreadyDone) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF2ECC71),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Absen Pulang Tercatat',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2ECC71),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Jam pulang $_checkoutTime',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF444444),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else if (!_isCheckoutAvailable) ...[
            // Belum waktunya — tampilkan countdown
            const Text(
              'Belum waktunya pulang',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _navyDark,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2340).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Tunggu hingga',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    countdown,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _navyDark,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Sudah waktunya — siap absen
            const Text(
              'Siap absen pulang',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _navyDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Jam sekarang $_todayTimeLabel',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],

          const SizedBox(height: 20),

          // ── Tombol absen ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isSubmitting || !canTap) ? null : _handleCheckout,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      alreadyDone
                          ? Icons.check
                          : canTap
                          ? Icons.login
                          : Icons.lock,
                      size: 18,
                    ),
              label: Text(
                alreadyDone ? 'Sudah Absen Pulang' : 'Tap untuk Absen Pulang',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: alreadyDone
                    ? Colors.grey.shade300
                    : canTap
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFF1A2340).withOpacity(0.3),
                foregroundColor: alreadyDone
                    ? Colors.grey.shade600
                    : Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Status GPS ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _locationStatus == 'Terdeteksi'
                  ? const Color(0xFFE8F8F0)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  _locationStatus == 'Terdeteksi'
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                  color: _locationStatus == 'Terdeteksi'
                      ? const Color(0xFF2ECC71)
                      : Colors.grey,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationStatus == 'Terdeteksi'
                        ? 'GPS terdeteksi ✓'
                        : _locationMessage,
                    style: TextStyle(
                      fontSize: 13,
                      color: _locationStatus == 'Terdeteksi'
                          ? const Color(0xFF2ECC71)
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Checkin time info ────────────────────────────────────────────
          if (_checkinTime != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.login, color: Colors.blue.shade400, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Absen masuk: $_checkinTime',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),
          ],

          // ── Error ────────────────────────────────────────────────────────
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade400,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}