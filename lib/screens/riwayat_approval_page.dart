import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../utils/constants.dart';
import 'approval_pengajuan_page.dart';

class RiwayatApprovalPage extends StatefulWidget {
  const RiwayatApprovalPage({super.key});

  @override
  State<RiwayatApprovalPage> createState() => _RiwayatApprovalPageState();
}

class _RiwayatApprovalPageState extends State<RiwayatApprovalPage> {
  static const Color _navyDark = Color(0xFF1A2340);
  static const Color _navyMid = Color(0xFF243050);
  static const Color _navyLight = Color(0xFF2E3D63);

  bool _isLoading = true;
  String? _errorMessage;

  int _currentPage = 1;
  int _lastPage = 1;
  bool _isFetchingMore = false;
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _history = [];

  // ── Filter tanggal ──
  DateTimeRange? _filterRange;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _currentPage < _lastPage) {
      _fetchMoreHistory();
    }
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentPage = 1;
      _history.clear();
    });
    await _doFetch(page: 1);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchMoreHistory() async {
    if (_isFetchingMore || _currentPage >= _lastPage) return;
    setState(() => _isFetchingMore = true);
    await _doFetch(page: _currentPage + 1);
    if (mounted) setState(() => _isFetchingMore = false);
  }

  Future<void> _doFetch({required int page}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('token');
      if (token == null)
        throw Exception('Token tidak ditemukan. Silakan login ulang.');

      final queryParams = <String, String>{'page': '$page', 'per_page': '10'};

      final uri = Uri.parse(
        '${AppConstants.baseUrl}/leave/approvals',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final dataWrapper = responseData['data'];
        List<dynamic> fetchedList = [];

        if (dataWrapper is Map) {
          final inner = dataWrapper['data'];
          if (inner is List) fetchedList = inner;
          _currentPage = (dataWrapper['current_page'] as num?)?.toInt() ?? page;
          _lastPage = (dataWrapper['last_page'] as num?)?.toInt() ?? 1;
        } else if (dataWrapper is List) {
          fetchedList = dataWrapper;
          _currentPage = 1;
          _lastPage = 1;
        }

        final parsed = fetchedList.map((item) {
          final map = item as Map<String, dynamic>;
          final rawStatus = map['status']?.toString() ?? '';

          // attachment bisa null atau string URL
          final attachmentRaw = map['attachment'];
          final attachment =
              (attachmentRaw != null &&
                  attachmentRaw.toString().isNotEmpty &&
                  attachmentRaw.toString() != 'null')
              ? _cleanUrl(attachmentRaw.toString())
              : null;

          return {
            'id': map['id']?.toString() ?? '',
            'user_name': map['user_name']?.toString() ?? '',
            'department': map['department']?.toString() ?? '',
            'user_nik': map['user_nik']?.toString() ?? '',
            'type': _capitalizeFirst(map['type']?.toString() ?? 'Izin'),
            'reason': map['reason']?.toString() ?? '',
            'start_date': map['start_date']?.toString(),
            'end_date': map['end_date']?.toString(),
            'date': _buildDateRange(
              map['start_date']?.toString(),
              map['end_date']?.toString(),
            ),
            'status_raw': rawStatus,
            'status': _mapStatusToDisplay(rawStatus),
            'attachment': attachment, // null jika kosong
            'created_at': map['created_at']?.toString() ?? '',
          };
        }).toList();

        if (mounted) {
          setState(() {
            if (page == 1) {
              _history
                ..clear()
                ..addAll(parsed);
            } else {
              _history.addAll(parsed);
            }
          });
        }
      } else if (response.statusCode == 401) {
        throw Exception('Sesi habis. Silakan login ulang.');
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Gagal memuat data riwayat.');
      }
    } catch (e) {
      if (mounted)
        setState(
          () => _errorMessage = e.toString().replaceAll('Exception: ', ''),
        );
    }
  }

  // ── Helpers ──

  String _cleanUrl(String url) {
    if (url.isEmpty) return '';
    const railwayPrefix =
        'https://absensi-app-production-d8b2.up.railway.app/storage/';
    if (url.startsWith(railwayPrefix)) {
      return url.substring(railwayPrefix.length);
    }
    return url;
  }

  String _mapStatusToDisplay(String raw) {
    switch (raw) {
      case 'Approved':
        return 'Disetujui';
      case 'Rejected':
        return 'Ditolak';
      case 'Pending':
        return 'Menunggu';
      default:
        return raw;
    }
  }

  String _capitalizeFirst(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  String _buildDateRange(String? start, String? end) =>
      '${_formatDate(start)} – ${_formatDate(end)}';

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Tidak tersedia';
    final date = DateTime.tryParse(dateString);
    if (date == null) return dateString;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatCreatedAt(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    final date = DateTime.tryParse(dateString);
    if (date == null) return dateString;
    final days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ags',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // ── Filter tanggal: helpers ──

  /// Daftar riwayat yang sudah difilter berdasarkan _filterRange (jika ada).
  /// Item ikut ditampilkan kalau rentang tanggalnya (start_date - end_date)
  /// beririsan dengan rentang filter yang dipilih user.
  List<Map<String, dynamic>> get _displayedHistory {
    if (_filterRange == null) return _history;

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

    return _history.where((item) {
      final start = DateTime.tryParse(item['start_date']?.toString() ?? '');
      if (start == null) return false;
      final end =
          DateTime.tryParse(item['end_date']?.toString() ?? '') ?? start;

      // true jika [start, end] beririsan dengan [filterStart, filterEnd]
      return !(end.isBefore(filterStart) || start.isAfter(filterEnd));
    }).toList();
  }

  // Dialog kalender custom berukuran kecil (bukan pakai showDatePicker
  // bawaan Flutter yang defaultnya lebar/tinggi hampir sepenuh layar di HP).
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
                    color: _navyMid,
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
                        primary: _navyLight,
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
  }

  void _clearDateFilter() {
    setState(() => _filterRange = null);
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
                    GestureDetector(
                      onTap: _pickDateFilter,
                      onLongPress:
                          _filterRange != null ? _clearDateFilter : null,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _filterRange != null
                              ? const Color(0xFF2ECC71).withOpacity(0.85)
                              : Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _filterRange != null
                              ? Icons.event_available
                              : Icons.calendar_today_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // ── Filter aktif banner ──
              if (_filterRange != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_alt,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Filter: ${_formatDate(_filterRange!.start.toIso8601String())} – '
                            '${_formatDate(_filterRange!.end.toIso8601String())}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _clearDateFilter,
                          child: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Error banner ──
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        GestureDetector(
                          onTap: _fetchHistory,
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
                    : _buildHistoryList(),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      onSelected: (value) {
        if (value == 'approval') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const ApprovalPengajuanPage(),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'riwayat',
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: _navyDark),
              const SizedBox(width: 8),
              const Text(
                'Riwayat Approval',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A2340),
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
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'approval',
          child: Row(
            children: [
              Icon(
                Icons.approval_outlined,
                size: 18,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Approval Pengajuan',
                style: TextStyle(color: Colors.grey.shade700),
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
              'Riwayat Approval Pengajuan',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(width: 6),
            Icon(Icons.expand_more, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    final displayed = _displayedHistory;

    if (displayed.isEmpty) {
      final bool isFiltering = _filterRange != null;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltering ? Icons.search_off : Icons.history,
              color: Colors.white38,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              isFiltering
                  ? 'Tidak ada riwayat pada rentang tanggal ini.'
                  : 'Belum ada riwayat approval.',
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: isFiltering ? _clearDateFilter : _fetchHistory,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isFiltering ? 'Hapus Filter' : 'Muat Ulang',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchHistory(),
      color: Colors.white,
      backgroundColor: _navyMid,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: displayed.length + (_isFetchingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == displayed.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );
          }
          return _buildHistoryCard(context, displayed[i]);
        },
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, Map<String, dynamic> item) {
    final statusRaw = item['status_raw']?.toString() ?? '';
    final statusDisplay = item['status']?.toString() ?? '';

    final Color statusColor;
    final Color statusBg;
    final Color statusBorder;
    final IconData statusIcon;

    switch (statusRaw) {
      case 'Approved':
        statusColor = const Color(0xFF1A9456);
        statusBg = const Color(0xFFE8F8F0);
        statusBorder = const Color(0xFF2ECC71);
        statusIcon = Icons.check_circle_outline;
        break;
      case 'Pending':
        statusColor = const Color(0xFFE65100);
        statusBg = const Color(0xFFFFF3E0);
        statusBorder = const Color(0xFFFF9800);
        statusIcon = Icons.access_time_outlined;
        break;
      case 'Rejected':
      default:
        statusColor = Colors.red.shade700;
        statusBg = Colors.red.shade50;
        statusBorder = Colors.red.shade200;
        statusIcon = Icons.cancel_outlined;
        break;
    }

    final type = item['type']?.toString() ?? '';
    final Color typeBadgeColor;
    switch (type.toLowerCase()) {
      case 'izin':
        typeBadgeColor = const Color(0xFFFFC107);
        break;
      case 'sakit':
        typeBadgeColor = const Color(0xFFEF5350);
        break;
      case 'cuti':
        typeBadgeColor = const Color(0xFF42A5F5);
        break;
      default:
        typeBadgeColor = const Color(0xFF78909C);
    }

    final userName = item['user_name']?.toString() ?? '';
    final department = item['department']?.toString() ?? '';
    final createdAt = _formatCreatedAt(item['created_at']?.toString());
    final attachment = item['attachment']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris 1: nama + tanggal + badge status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (department.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        department,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    createdAt,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 13, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusDisplay,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Baris 2: range tanggal
          Row(
            children: [
              const Icon(Icons.date_range, size: 14, color: Color(0xFF78909C)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item['date']?.toString() ?? 'Tidak tersedia',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
            ],
          ),

          // Baris 3: alasan
          if (item['reason'] != null &&
              item['reason'].toString().isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes, size: 14, color: Color(0xFF78909C)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item['reason'].toString(),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // Baris 4: badge tipe + badge aksi
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: typeBadgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: typeBadgeColor.withOpacity(0.5),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: typeBadgeColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Container(
              //   padding: const EdgeInsets.symmetric(
              //     horizontal: 10,
              //     vertical: 4,
              //   ),
              //   decoration: BoxDecoration(
              //     color: Colors.grey.shade100,
              //     borderRadius: BorderRadius.circular(8),
              //     border: Border.all(color: Colors.grey.shade300, width: 0.8),
              //   ),
              //   // child: Text(
              //   //   'Buat',
              //   //   style: TextStyle(
              //   //     fontSize: 11,
              //   //     fontWeight: FontWeight.bold,
              //   //     color: Colors.grey.shade600,
              //   //   ),
              //   // ),
              // ),
            ],
          ),

          // Lampiran
          if (attachment != null && attachment.isNotEmpty)
            _buildAttachment(context, attachment),
        ],
      ),
    );
  }

  void _showAttachmentFullscreen(BuildContext context, String imageUrl) {
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

  Widget _buildAttachment(BuildContext context, String? url) {
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file, size: 14, color: Color(0xFF4CAF50)),
              const SizedBox(width: 4),
              Text(
                'Bukti Lampiran',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _showAttachmentFullscreen(context, url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 140,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: Colors.grey.shade100,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade100,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              color: Colors.grey.shade400,
                              size: 32,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Gagal memuat gambar',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.zoom_in,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}