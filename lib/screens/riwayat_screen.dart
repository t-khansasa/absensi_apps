import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/constants.dart';
import 'detail_riwayat_screen.dart';
import 'leave_history_screen.dart';

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  List<Map<String, dynamic>> _riwayat = [];
  bool _isLoading = true;

  late int _selectedMonth;
  late int _selectedYear;

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
    _fetchRiwayat();
  }

  Future<void> _fetchRiwayat() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('Token tidak ditemukan.');

      final uri = Uri.parse('${AppConstants.baseUrl}/attendance').replace(
        queryParameters: {
          'month': _selectedMonth.toString(),
          'year': _selectedYear.toString(),
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
        final decoded = jsonDecode(response.body);
        final List<dynamic> raw = decoded['data'] as List<dynamic>? ?? [];
        setState(() {
          _riwayat = raw.map((item) {
            final m = item as Map<String, dynamic>;
            return {
              'id': m['id'],
              'date': m['date']?.toString(),
              'office_name': m['office_name']?.toString() ?? 'Kantor',
              'time_in': m['time_in']?.toString(),
              'time_out': m['time_out']?.toString(),
              'is_late': m['is_late'] == true,
              'face_verified': m['face_verified'] == true,
              'status': m['status']?.toString() ?? 'Belum Checkout',
              'pic_in': m['pic_in']?.toString(),
              'pic_out': m['pic_out']?.toString(),
              'lat_in': m['lat_in']?.toString() ?? '0.0',
              'long_in': m['long_in']?.toString() ?? '0.0',
              'lat_out': m['lat_out']?.toString() ?? '0.0',
              'long_out': m['long_out']?.toString() ?? '0.0',
            };
          }).toList();
        });
      } else {
        setState(() => _riwayat = []);
      }
    } catch (e) {
      debugPrint('Gagal memuat riwayat: $e');
      setState(() => _riwayat = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Picker bulan ──────────────────────────────────────────────────────────
  Future<void> _pickMonth() async {
    int tempMonth = _selectedMonth;
    int tempYear = _selectedYear;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setInner(() => tempYear--),
              ),
              Text(
                '$tempYear',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setInner(() => tempYear++),
              ),
            ],
          ),
          content: SizedBox(
            width: 280,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2,
              children: List.generate(12, (i) {
                final isSelected = (i + 1) == tempMonth;
                return GestureDetector(
                  onTap: () => setInner(() => tempMonth = i + 1),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? _darkBlue : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _monthShort[i],
                      style: TextStyle(
                        color: isSelected ? Colors.white : _darkBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _darkBlue),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedMonth = tempMonth;
                  _selectedYear = tempYear;
                });
                _fetchRiwayat();
              },
              child: const Text('Pilih', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
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
              Icon(Icons.access_time, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Riwayat Absensi',
                style: TextStyle(
                  color: Colors.white,
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
              Icon(Icons.description_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'Riwayat Pengajuan',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == 'pengajuan' && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LeaveHistoryScreen()),
      );
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

  Color _borderColor(Map<String, dynamic> item) {
    final dynamic isLateRaw = item['is_late'];
    final bool isLate =
        isLateRaw == true ||
        isLateRaw == 1 ||
        isLateRaw == '1' ||
        isLateRaw == 'true' ||
        isLateRaw.toString().toLowerCase() == 'true' ||
        isLateRaw.toString() == '1';

    return isLate ? Colors.red.shade400 : Colors.green.shade400;
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
                        'Riwayat Absensi',
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

          // Icon kalender
          GestureDetector(
            onTap: _pickMonth,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_month_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
                Text(
                  '${_monthNames[_selectedMonth - 1]} $_selectedYear',
                  style: const TextStyle(
                    color: _darkBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _fetchRiwayat,
                  child: const Icon(Icons.refresh, color: _darkBlue, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _darkBlue),
                  )
                : _riwayat.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _fetchRiwayat,
                    color: _darkBlue,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                      itemCount: _riwayat.length,
                      itemBuilder: (_, i) => _buildCard(_riwayat[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final picIn = item['pic_in'] as String?;
    final borderColor = _borderColor(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2.5),
            color: Colors.grey.shade200,
          ),
          child: ClipOval(
            child: picIn != null && picIn.isNotEmpty
                ? Image.network(
                    picIn,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.person, color: Colors.grey.shade400),
                  )
                : Icon(Icons.person, color: Colors.grey.shade400),
          ),
        ),
        title: Text(
          _dayLabel(item['date']?.toString()),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: _darkBlue,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['office_name'] ?? 'Kantor',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            if (item['time_in'] != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.login, size: 11, color: Colors.green.shade600),
                  const SizedBox(width: 3),
                  Text(
                    item['time_in']!.substring(0, 5),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade600,
                    ),
                  ),
                  if (item['time_out'] != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.logout, size: 11, color: Colors.red.shade400),
                    const SizedBox(width: 3),
                    Text(
                      item['time_out']!.substring(0, 5),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        // Tombol Detail → ke DetailRiwayatScreen
        trailing: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetailRiwayatScreen(data: item)),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _darkBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Detail',
              style: TextStyle(
                color: _darkBlue,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
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
            'Tidak ada absensi',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_monthNames[_selectedMonth - 1]} $_selectedYear',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
