import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../utils/constants.dart';
import 'riwayat_approval_page.dart';

class ApprovalPengajuanPage extends StatefulWidget {
  const ApprovalPengajuanPage({super.key});

  @override
  State<ApprovalPengajuanPage> createState() => _ApprovalPengajuanPageState();
}

class _ApprovalPengajuanPageState extends State<ApprovalPengajuanPage> {
  static const Color _navyDark = Color(0xFF0A2246);
  static const Color _navyMid = Color(0xFF1D4461);
  static const Color _navyLight = Color(0xFF90CAF9);

  bool _isLoading = true;
  String? _errorMessage;

  final List<Map<String, dynamic>> _requests = [];
  // ID yang sedang diproses (untuk disable tombol saat loading)
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchPendingApprovals();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA
  // ═══════════════════════════════════════════════════════════════════════════

  List<dynamic> _extractDataList(dynamic rawData) {
    if (rawData is List) return rawData;
    if (rawData is Map) {
      final inner = rawData['data'] ?? rawData['items'];
      if (inner is List) return inner;
      // Laravel paginate: data.data
      if (inner is Map) {
        final nested = inner['data'];
        if (nested is List) return nested;
      }
    }
    return [];
  }

  Future<void> _fetchPendingApprovals() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('token');
      if (token == null)
        throw Exception('Token tidak ditemukan. Silakan login ulang.');

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/leave/approvals'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      debugPrint('📦 APPROVALS: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final List<dynamic> fetchedData = _extractDataList(
          responseData['data'],
        );

        _requests.clear();
        for (final item in fetchedData) {
          final map = item as Map<String, dynamic>;
          // Backend kirim: 'Pending' | 'Approved' | 'Rejected'
          final rawStatus = map['status']?.toString() ?? '';

          // Halaman ini hanya tampilkan yang Pending
          if (rawStatus != 'Pending') continue;

          final startDate = map['start_date']?.toString();
          final endDate = map['end_date']?.toString();

          _requests.add({
            'id': map['id']?.toString() ?? '',
            'name':
                map['user_name']?.toString() ??
                map['name']?.toString() ??
                'Karyawan',
            'nik': map['user_nik']?.toString() ?? '',
            'department': map['department']?.toString() ?? '',
            'position': map['position']?.toString() ?? 'Junior Staff IT',
            'type': map['type']?.toString() ?? 'Izin',
            'reason': map['reason']?.toString() ?? '',
            'start_date': startDate,
            'end_date': endDate,
            'date': _buildDateRange(startDate, endDate),
            'created_at': map['created_at']?.toString() ?? '',
            // Backend sudah kembalikan full URL
            'attachment': _cleanUrl(map['attachment']?.toString() ?? ''),
            'status': rawStatus,
          });
        }
      } else if (response.statusCode == 401) {
        throw Exception('Sesi habis. Silakan login ulang.');
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Gagal memuat data.');
      }
    } catch (e) {
      _requests.clear();
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processApproval(String id, bool approve) async {
    if (_processingIds.contains(id)) return;
    setState(() => _processingIds.add(id));

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('token');
      if (token == null) throw Exception('Token tidak ditemukan.');

      final endpoint = approve ? 'approve' : 'reject';
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/leave/$id/$endpoint'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && (data['success'] == true)) {
        // Hapus dari list setelah berhasil
        if (mounted) {
          setState(() {
            _requests.removeWhere((item) => item['id'] == id);
            _processingIds.remove(id);
          });
          _showSnackbar(
            approve
                ? 'Pengajuan berhasil disetujui.'
                : 'Pengajuan berhasil ditolak.',
            approve ? Colors.green : Colors.red,
          );
        }
      } else {
        throw Exception(data['message'] ?? 'Gagal memproses.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(id));
        _showSnackbar(e.toString().replaceAll('Exception: ', ''), Colors.red);
      }
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _cleanUrl(String url) {
    if (url.isEmpty) return '';
    const railwayPrefix =
        'https://absensi-app-production-d8b2.up.railway.app/storage/';
    if (url.startsWith(railwayPrefix)) {
      return url.substring(railwayPrefix.length);
    }
    return url;
  }

  String _buildDateRange(String? start, String? end) =>
      '${_formatDate(start)} - ${_formatDate(end)}';

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Tidak tersedia';
    final date = DateTime.tryParse(dateString);
    if (date == null) return dateString;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  /// Format: "Senin, 12 Mar 2026"
  String _formatCreatedAt(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    const months = [
      '',
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
    // Hari: weekday → 1=Sen ... 7=Min
    final dayLabel = days[date.weekday - 1];
    return '$dayLabel, ${date.day} ${months[date.month]} ${date.year}';
  }

  Color _typeBadgeColor(String type) {
    switch (type.toLowerCase()) {
      case 'izin':
        return const Color(0xFFFFC107);
      case 'sakit':
        return const Color(0xFFEF5350);
      case 'cuti':
        return const Color(0xFF42A5F5);
      default:
        return const Color(0xFF78909C);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_navyDark, _navyMid, _navyLight],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── App Bar ──
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
                    Expanded(child: _buildNavDropdown()),
                    const SizedBox(width: 8),
                    // Tombol refresh
                    GestureDetector(
                      onTap: _fetchPendingApprovals,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Error banner ──
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _fetchPendingApprovals,
                          child: const Text(
                            'Coba lagi',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── List ──
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchPendingApprovals,
                        color: _navyDark,
                        backgroundColor: Colors.white,
                        child: _buildList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavDropdown() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      elevation: 8,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      color: _navyDark.withOpacity(0.92),
      onSelected: (value) {
        if (value == 'riwayat') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RiwayatApprovalPage()),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'riwayat',
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text(
                'Riwayat Pengajuan',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        PopupMenuDivider(color: Colors.white.withOpacity(0.2)),
        PopupMenuItem(
          value: 'approval',
          child: Row(
            children: [
              const Icon(
                Icons.approval_outlined,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              const Text(
                'Approval Pengajuan',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF2ECC71),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _navyMid.withOpacity(0.55),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Approval Pengajuan',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.expand_more, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white38, size: 60),
            const SizedBox(height: 12),
            const Text(
              'Tidak ada pengajuan masuk.',
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _fetchPendingApprovals,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Muat Ulang',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _buildCard(_requests[i]),
    );
  }

  // ── Kartu sesuai desain gambar ──
  Widget _buildCard(Map<String, dynamic> item) {
    final String id = item['id']?.toString() ?? '';
    final String name = item['name']?.toString() ?? 'Karyawan';
    final String department = item['department']?.toString() ?? '';
    final String position = item['position']?.toString() ?? 'Junior Staff IT';
    final String type = item['type']?.toString() ?? 'Izin';
    final String date = item['date']?.toString() ?? '';
    final String reason = item['reason']?.toString() ?? '';
    final String createdAt = _formatCreatedAt(item['created_at']?.toString());
    final String? attachment = item['attachment']?.toString();
    final bool hasAttachment = attachment != null && attachment.isNotEmpty;
    final bool isProcessing = _processingIds.contains(id);

    final Color badgeColor = _typeBadgeColor(type);

    // Label jabatan + departemen
    final String subTitle = [
      if (position.isNotEmpty) position,
      if (department.isNotEmpty) department,
    ].join(' • ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Baris atas: nama + tanggal pengajuan ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2340),
                      ),
                    ),
                    if (subTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (createdAt.isNotEmpty)
                Text(
                  createdAt,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 10),

          // ── Tanggal izin ──
          Row(
            children: [
              const Icon(Icons.date_range, size: 14, color: Color(0xFF78909C)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
              // Badge tipe (Izin / Sakit / Cuti)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: badgeColor.withOpacity(0.6),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor == const Color(0xFFFFC107)
                        ? const Color(0xFF8B6800) // amber gelap agar terbaca
                        : badgeColor,
                  ),
                ),
              ),
              // Badge lampiran (jika ada)
              if (hasAttachment) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showAttachmentFullscreen(attachment),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.green.withOpacity(0.5),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.attach_file, size: 11, color: Colors.green),
                        SizedBox(width: 3),
                        Text(
                          'Bukti',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ── Alasan ──
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reason,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],

          const SizedBox(height: 14),

          // ── Tombol Setujui & Tolak ──
          isProcessing
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1A2340),
                      ),
                    ),
                  ),
                )
              : Row(
                  children: [
                    // Tombol Setujui
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _confirmAction(id, true),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F8F0),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF2ECC71),
                              width: 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Setujui',
                            style: TextStyle(
                              color: Color(0xFF1A9456),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Tombol Tolak
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _confirmAction(id, false),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F0),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFEF5350),
                              width: 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Tolak',
                            style: TextStyle(
                              color: Color(0xFFD32F2F),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
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

  /// Dialog konfirmasi sebelum approve/reject
  void _confirmAction(String id, bool approve) {
    final item = _requests.firstWhere((r) => r['id'] == id, orElse: () => {});
    final name = item['name']?.toString() ?? 'karyawan ini';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          approve ? 'Setujui Pengajuan?' : 'Tolak Pengajuan?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          approve
              ? 'Anda akan menyetujui pengajuan dari $name.'
              : 'Anda akan menolak pengajuan dari $name.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Batal', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _processApproval(id, approve);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: approve
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFFEF5350),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(approve ? 'Ya, Setujui' : 'Ya, Tolak'),
          ),
        ],
      ),
    );
  }

  void _showAttachmentFullscreen(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 48,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Gagal memuat gambar',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}