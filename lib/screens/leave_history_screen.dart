import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../utils/constants.dart';
import 'riwayat_screen.dart';

class _MonthYear {
  final int month;
  final int year;
  const _MonthYear(this.month, this.year);
}

class LeaveHistoryScreen extends StatefulWidget {
  const LeaveHistoryScreen({super.key});

  @override
  State<LeaveHistoryScreen> createState() => _LeaveHistoryScreenState();
}

class _LeaveHistoryScreenState extends State<LeaveHistoryScreen> {
  List<dynamic> listPengajuan = [];
  bool isLoading = true;

  late int _selectedMonth;
  late int _selectedYear;

  // Filter rentang tanggal (menggantikan picker bulan)
  DateTimeRange? _filterRange;

  // ── Samakan palet warna dengan RiwayatScreen ──────────────────────────────
  static const Color _darkBlue = Color(0xFF0A2246);
  static const Color _midBlue = Color(0xFF1D4461);
  static const Color _lightBlue = Color(0xFF90CAF9);

  static const List<String> _monthNames = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  static const List<String> _monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  static const List<String> _dayNames = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;
    _fetchRiwayatPengajuan();
  }

  // Helper untuk mengubah path database menjadi URL server penuh
  String _resolveAssetUrl(dynamic value) {
    final path = value?.toString() ?? '';
    if (path.isEmpty) return '';

    const railwayPrefix =
        'https://absensi-app-production-d8b2.up.railway.app/storage/';
    if (path.startsWith(railwayPrefix)) {
      return path.substring(railwayPrefix.length);
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return 'http://${AppConstants.baseIp}/absensi/public/storage/$path';
  }

  /// Daftar bulan+tahun yang perlu di-fetch dari server supaya mencakup
  /// seluruh rentang tanggal filter (endpoint hanya mendukung month/year).
  List<_MonthYear> _monthsBetween(DateTime start, DateTime end) {
    final result = <_MonthYear>[];
    DateTime cursor = DateTime(start.year, start.month);
    final last = DateTime(end.year, end.month);
    while (!cursor.isAfter(last)) {
      result.add(_MonthYear(cursor.month, cursor.year));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return result;
  }

  Future<void> _fetchRiwayatPengajuan() async {
    if (mounted) setState(() => isLoading = true);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token');

    if (token == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final List<_MonthYear> monthsToFetch = _filterRange != null
          ? _monthsBetween(_filterRange!.start, _filterRange!.end)
          : [_MonthYear(_selectedMonth, _selectedYear)];

      final List<dynamic> merged = [];

      for (final my in monthsToFetch) {
        final uri = Uri.parse('${AppConstants.baseUrl}/leave').replace(
          queryParameters: {
            'month': my.month.toString(),
            'year': my.year.toString(),
          },
        );
        final response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> responseData = jsonDecode(response.body);
          if (responseData['data'] is List) {
            merged.addAll(responseData['data']);
          } else if (responseData['data'] is Map &&
              responseData['data']['data'] is List) {
            merged.addAll(responseData['data']['data']);
          }
        }
      }

      List<dynamic> result = merged;

      // Filter presisi sesuai tanggal mulai–akhir yang dipilih user
      if (_filterRange != null) {
        final filterStart = DateTime(
          _filterRange!.start.year,
          _filterRange!.start.month,
          _filterRange!.start.day,
        );
        final filterEnd = DateTime(
          _filterRange!.end.year,
          _filterRange!.end.month,
          _filterRange!.end.day,
          23,
          59,
          59,
        );

        result = merged.where((item) {
          final map = item as Map<String, dynamic>;
          final start = DateTime.tryParse(
            map['start_date']?.toString() ?? '',
          );
          if (start == null) return false;
          final end =
              DateTime.tryParse(map['end_date']?.toString() ?? '') ?? start;
          return !(end.isBefore(filterStart) || start.isAfter(filterEnd));
        }).toList();
      }

      if (!mounted) return;
      setState(() {
        listPengajuan = result;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Gagal memuat riwayat pengajuan: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Helper untuk normalisasi status dari API
  String _getLabelStatus(String statusRaw) {
    switch (statusRaw) {
      case 'approved':
      case 'disetujui':
        return 'Disetujui';
      case 'rejected':
      case 'ditolak':
      case 'tidak disetujui':
        return 'Tidak Disetujui';
      default:
        return 'Pending';
    }
  }

  Color _getColorStatus(String statusRaw) {
    switch (statusRaw) {
      case 'approved':
      case 'disetujui':
        return Colors.green.shade600;
      case 'rejected':
      case 'ditolak':
      case 'tidak disetujui':
        return Colors.red.shade400;
      default:
        return Colors.orange.shade700;
    }
  }

  String _dayLabel(String? dateStr) {
    final d = DateTime.tryParse(dateStr ?? '');
    if (d == null) return '-';
    return '${_dayNames[d.weekday - 1]}, '
        '${d.day.toString().padLeft(2, '0')} '
        '${_monthShort[d.month - 1]} '
        '${d.year}';
  }

  String _shortDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  // ─── Popup kecil pilih tanggal (sama seperti di RiwayatApprovalPage) ─────
  Future<DateTime?> _showCompactDatePicker({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required String title,
    required String confirmText,
  }) {
    DateTime selected = initialDate;
    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 80,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: _midBlue,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Flexible(
                  child: Theme(
                    data: Theme.of(dialogContext).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: _darkBlue,
                        onPrimary: Colors.white,
                      ),
                    ),
                    child: CalendarDatePicker(
                      initialDate: selected,
                      firstDate: firstDate,
                      lastDate: lastDate,
                      onDateChanged: (d) => selected = d,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Batal'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(selected),
                        child: Text(confirmText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDateFilter() async {
    final now = DateTime.now();

    final start = await _showCompactDatePicker(
      initialDate: _filterRange?.start ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      title: 'Pilih Tanggal Mulai',
      confirmText: 'Lanjut',
    );
    if (start == null || !mounted) return;

    final end = await _showCompactDatePicker(
      initialDate: _filterRange != null && !_filterRange!.end.isBefore(start)
          ? _filterRange!.end
          : start,
      firstDate: start,
      lastDate: DateTime(2100),
      title: 'Pilih Tanggal Akhir',
      confirmText: 'Terapkan',
    );
    if (end == null || !mounted) return;

    setState(() => _filterRange = DateTimeRange(start: start, end: end));
    _fetchRiwayatPengajuan();
  }

  void _clearDateFilter() {
    setState(() => _filterRange = null);
    _fetchRiwayatPengajuan();
  }

  // ─── Dropdown menu: Riwayat Absensi / Riwayat Pengajuan ───────────────────
  void _showMenuDropdown(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: _darkBlue,
      items: [
        PopupMenuItem(
          value: 'absensi',
          child: Row(
            children: const [
              Icon(Icons.access_time, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'Riwayat Absensi',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pengajuan',
          child: Row(
            children: const [
              Icon(Icons.description_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Riwayat Pengajuan',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == 'absensi' && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RiwayatScreen()),
      );
    }
  }

  Future<void> _bukaBuktiLampiran(String? attachmentPath) async {
    debugPrint("🔍 attachmentPath raw: $attachmentPath");
    if (attachmentPath == null || attachmentPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Pengajuan ini tidak memiliki lampiran bukti."),
        ),
      );
      return;
    }

    final String fullUrl = _resolveAssetUrl(attachmentPath);
    debugPrint("🔍 fullUrl hasil resolve: $fullUrl");
    final Uri url = Uri.parse(fullUrl);

    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint("Berhasil membuka lampiran: $fullUrl");
      } else {
        throw 'Could not launch $fullUrl';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Gagal membuka file bukti: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_darkBlue, _midBlue, _lightBlue],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header disamakan persis dengan RiwayatScreen ──────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Dropdown judul — tap munculkan menu
          Expanded(
            child: Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => _showMenuDropdown(ctx),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: const [
                      Text(
                        'Riwayat Pengajuan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Icon kalender — sekarang buka popup filter rentang tanggal
          GestureDetector(
            onTap: _pickDateFilter,
            onLongPress: _filterRange != null ? _clearDateFilter : null,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _filterRange != null
                    ? Colors.greenAccent.withOpacity(0.35)
                    : Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _filterRange != null
                    ? Icons.event_available
                    : Icons.calendar_month_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Body putih melengkung, sama dengan RiwayatScreen ──────────────────────
  Widget _buildBody() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4F8),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _filterRange != null
                        ? '${_shortDate(_filterRange!.start)} – ${_shortDate(_filterRange!.end)}'
                        : '${_monthNames[_selectedMonth - 1]} $_selectedYear',
                    style: const TextStyle(
                      color: _darkBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (_filterRange != null)
                  GestureDetector(
                    onTap: _clearDateFilter,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        Icons.close,
                        color: _darkBlue.withOpacity(0.7),
                        size: 18,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: _fetchRiwayatPengajuan,
                  child: const Icon(Icons.refresh, color: _darkBlue, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _darkBlue),
                  )
                : listPengajuan.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _fetchRiwayatPengajuan,
                    color: _darkBlue,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                      itemCount: listPengajuan.length,
                      itemBuilder: (context, index) {
                        final item =
                            listPengajuan[index] as Map<String, dynamic>;
                        return _buildCard(item);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Kartu pengajuan dengan gaya yang sama seperti kartu riwayat absensi ───
  Widget _buildCard(Map<String, dynamic> item) {
    final String statusRaw = (item['status'] ?? 'pending')
        .toString()
        .trim()
        .toLowerCase();

    final String tanggalInput =
        item['created_at_formatted']?.toString() ??
        _dayLabel(item['start_date']?.toString());

    final String tanggalMulai = item['start_date']?.toString() ?? '';
    final String tanggalSelesai = item['end_date']?.toString() ?? '';

    final String jenis = (item['type'] ?? 'Izin').toString();

    final String alasan = (item['reason'] ?? item['description'] ?? '')
        .toString()
        .trim();

    final String? buktiPath =
        item['attachment'] ?? item['bukti'] ?? item['file'];

    final Color statusColor = _getColorStatus(statusRaw);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// ================== BAGIAN ATAS ==================
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tanggalInput,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      "$tanggalMulai - $tanggalSelesai",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      alasan.isEmpty ? "-" : alasan,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              Text(
                _getLabelStatus(statusRaw),
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          /// ================== BAGIAN BAWAH ==================
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF59D),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber, width: 1),
                ),
                child: Text(
                  jenis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(width: 20),

              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _bukaBuktiLampiran(buktiPath),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    "Bukti",
                    style: TextStyle(
                      color: Color(0xFF0A4A9C),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada riwayat pengajuan',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _filterRange != null
                ? '${_shortDate(_filterRange!.start)} – ${_shortDate(_filterRange!.end)}'
                : '${_monthNames[_selectedMonth - 1]} $_selectedYear',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }
}