import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/constants.dart';
import 'approval_pengajuan_page.dart';
import 'absen_pulang_screen.dart';
import 'face_registration_screen.dart';
import 'leave_request_screen.dart';
import 'leave_history_screen.dart';
import 'profile_screen.dart';
import 'riwayat_screen.dart';
import 'scan_screen.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const DashboardPage({super.key, required this.userData});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> riwayat = [];
  bool isLoading = false;
  bool _isFaceRegistered = false;
  bool _checkingFaceStatus = true;
  Color themeColor = const Color(0xFF0A2246);
  String companyName = "PT. Surya Gaya Dharmaputra";
  String companyLogo = "";
  int _notificationCount = 0;
  int _currentIndex = 0;
  bool _canApprove = false;
  bool _checkingApprovalAccess = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGIKA UTAMA
  // ═══════════════════════════════════════════════════════════════════════════

  List<dynamic> _extractDataList(dynamic rawData) {
    if (rawData is List) return rawData;
    if (rawData is Map) {
      final nestedData = rawData['data'] ?? rawData['items'];
      if (nestedData is List) return nestedData;
    }
    return [];
  }

  String _resolveAssetUrl(dynamic value) {
    final path = value?.toString().trim() ?? '';
    if (path.isEmpty) return '';

    // ── FIX: bersihkan double prefix Railway + Cloudinary ──
    const railwayPrefix =
        'https://absensi-app-production-d8b2.up.railway.app/storage/';
    if (path.startsWith(railwayPrefix)) {
      final cleaned = path.substring(railwayPrefix.length);
      debugPrint('✅ Double prefix dibersihkan: $cleaned');
      return cleaned;
    }

    if (path.startsWith('http://') || path.startsWith('https://')) {
      debugPrint('✅ URL sudah lengkap, tidak ditambah prefix: $path');
      return path;
    }

    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final fullUrl =
        'http://${AppConstants.baseIp}/absensi/public/storage/$cleanPath';
    debugPrint('✅ URL relatif → dikonversi ke: $fullUrl');
    return fullUrl;
  }

  String? _extractLogoFromMap(Map<dynamic, dynamic> map) {
    const logoFields = [
      'logo',
      'image',
      'logo_url',
      'image_url',
      'photo',
      'avatar',
      'icon',
      'logo_path',
      'image_path',
    ];
    for (final field in logoFields) {
      final val = map[field]?.toString().trim();
      if (val != null && val.isNotEmpty) {
        debugPrint('✅ Logo ditemukan di field "$field": $val');
        return val;
      }
    }
    return null;
  }

  Map<String, dynamic> get _profileSafeUserData {
    Map<String, dynamic> namedValue(dynamic value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      if (value is String && value.isNotEmpty) return {'name': value};
      return {};
    }

    return {
      ...widget.userData,
      'company': namedValue(widget.userData['company']),
      'department': namedValue(widget.userData['department']),
      'position': namedValue(widget.userData['position']),
      'tenant': namedValue(widget.userData['tenant']),
    };
  }

  @override
  void initState() {
    super.initState();
    _loadBranding();
    _fetchRiwayat();
    _fetchCompanyLogo();
    _checkApprovalAccess();
    _checkFaceRegistrationStatus();
  }

  Future<void> _loadBranding() async {
    final prefs = await SharedPreferences.getInstance();

    final int? colorValue = prefs.getInt('theme_color');
    final Color resolvedColor = colorValue != null
        ? Color(colorValue)
        : const Color(0xFF0A2246);

    String? resolvedName;
    String? rawLogoPath;

    final company = widget.userData['company'];
    if (company is Map) {
      resolvedName = company['name']?.toString().trim();
      rawLogoPath = _extractLogoFromMap(company);
    } else if (company is String && company.isNotEmpty) {
      resolvedName = company;
    }
    resolvedName ??= widget.userData['company_name']?.toString().trim();

    if (resolvedName == null || resolvedName.isEmpty) {
      final tenant = widget.userData['tenant'];
      if (tenant is Map) {
        resolvedName = tenant['name']?.toString().trim();
        rawLogoPath ??= _extractLogoFromMap(tenant);
      } else if (tenant is String && tenant.isNotEmpty) {
        resolvedName = tenant;
      }
    }

    // if (rawLogoPath == null || rawLogoPath.isEmpty) {
    //   rawLogoPath = _extractLogoFromMap(widget.userData);
    // }

    debugPrint('🔍 rawLogoPath (sebelum resolve) : "$rawLogoPath"');
    final String resolvedLogo = (rawLogoPath != null && rawLogoPath.isNotEmpty)
        ? _resolveAssetUrl(rawLogoPath)
        : '';
    debugPrint('🔍 resolvedLogo (setelah resolve): "$resolvedLogo"');

    resolvedName ??= widget.userData['employer_name']?.toString().trim();
    resolvedName ??= prefs.getString('company_name');
    resolvedName ??= "PT. Surya Gaya Dharmaputra";

    debugPrint('🔍 userData keys   : ${widget.userData.keys.toList()}');
    debugPrint('🔍 company object  : ${widget.userData['company']}');
    debugPrint('🔍 tenant object   : ${widget.userData['tenant']}');
    debugPrint('🔍 resolvedName    : $resolvedName');

    if (!mounted) return;
    setState(() {
      themeColor = resolvedColor;
      companyName = resolvedName!;
      companyLogo = resolvedLogo;
    });
  }

  Future<void> _fetchCompanyLogo() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    final email = widget.userData['email']?.toString() ?? '';
    if (email.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/branding/$email'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      debugPrint('🔍 BRANDING RESPONSE: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final logoUrl = data['data']?['logo_url']?.toString() ?? '';

        String finalUrl = '';
        if (logoUrl.isNotEmpty) {
          if (logoUrl.startsWith('http://') || logoUrl.startsWith('https://')) {
            finalUrl = logoUrl;
          } else {
            final cleanPath = logoUrl.startsWith('/')
                ? logoUrl.substring(1)
                : logoUrl;
            finalUrl =
                'https://absensi-app-production-d8b2.up.railway.app/storage/$cleanPath';
          }
        }

        debugPrint('🔍 Logo URL final: $finalUrl');

        if (finalUrl.isNotEmpty && mounted) {
          setState(() => companyLogo = finalUrl);
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetch branding: $e');
    }
  }

  Future<void> _fetchRiwayat() async {
    const String url = '${AppConstants.baseUrl}/attendance';
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token');
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final List<dynamic> fetchedData = _extractDataList(
          responseData['data'],
        );

        if (!mounted) return;
        setState(() {
          riwayat = fetchedData.map((item) {
            final map = item as Map<String, dynamic>;
            final timeIn = map['time_in']?.toString();
            final timeOut = map['time_out']?.toString();
            return {
              "status": map['status']?.toString() ?? "Absensi Masuk",
              "waktu": timeIn ?? "--:--",
              "time_in": timeIn,
              "time_out": timeOut,
              "tanggal": map['date']?.toString() ?? "",
              "date": map['date']?.toString() ?? "",
              "lokasi": map['location']?.toString() ?? "Kantor",
              "office_name": map['office_name']?.toString() ?? "Kantor",
              "latitude":
                  map['lat_in']?.toString() ??
                  map['latitude']?.toString() ??
                  "0.0",
              "longitude":
                  map['long_in']?.toString() ??
                  map['longitude']?.toString() ??
                  "0.0",
              "lat_in": map['lat_in']?.toString() ?? "0.0",
              "long_in": map['long_in']?.toString() ?? "0.0",
              "lat_out": map['lat_out']?.toString() ?? "0.0",
              "long_out": map['long_out']?.toString() ?? "0.0",
              "image_url": _resolveAssetUrl(map['pic_in']),
              "pic_in": _resolveAssetUrl(map['pic_in']),
              "pic_out": _resolveAssetUrl(map['pic_out']),
              "is_late": map['is_late'],
              "face_verified": map['face_verified'],
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Gagal mengambil riwayat: $e");
    }
  }

  Future<void> _goToFaceRegistration() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FaceRegistrationScreen()),
    );
    if (res == true) {
      setState(() => _isFaceRegistered = true);
    }
  }

  Future<void> _checkFaceRegistrationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      if (mounted) setState(() => _checkingFaceStatus = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/face-embedding'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (mounted) {
        setState(() {
          _isFaceRegistered = response.statusCode == 200;
          _checkingFaceStatus = false;
        });
      }
    } catch (e) {
      debugPrint('Gagal cek status registrasi wajah: $e');
      if (mounted) setState(() => _checkingFaceStatus = false);
    }
  }

  Future<void> _checkApprovalAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      if (mounted) setState(() => _checkingApprovalAccess = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/leave/approvals'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      bool hasAccess = false;

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final List<dynamic> approvals = _extractDataList(responseData['data']);
        // Hanya anggap punya akses kalau memang ADA data
        // (artinya dia punya bawahan yang bisa dia approve)
        hasAccess = approvals.isNotEmpty;
      }

      if (!mounted) return;
      setState(() {
        _canApprove = hasAccess;
        _checkingApprovalAccess = false;
      });

      if (hasAccess) {
        _fetchNotificationCount();
      }
    } catch (e) {
      debugPrint('Gagal cek akses approval: $e');
      if (mounted) {
        setState(() {
          _canApprove = false;
          _checkingApprovalAccess = false;
        });
      }
    }
  }

  Future<void> _fetchNotificationCount() async {
    const String url = '${AppConstants.baseUrl}/leave/approvals';
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token');
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final List<dynamic> approvals = _extractDataList(responseData['data']);

        final pendingCount = approvals.where((item) {
          final map = item as Map<String, dynamic>;
          final status =
              (map['status']?.toString() ??
                      map['approval_status']?.toString() ??
                      '')
                  .toLowerCase();

          debugPrint('📋 Status approval item: "$status"');

          return !status.contains('approve') &&
              !status.contains('reject') &&
              !status.contains('disetujui') &&
              !status.contains('ditolak') &&
              !status.contains('accepted') &&
              !status.contains('declined') &&
              !status.contains('approved') &&
              !status.contains('rejected') &&
              status != '1' &&
              status != '2';
        }).length;

        debugPrint('🔔 Jumlah pending approval: $pendingCount');

        if (!mounted) return;
        setState(() => _notificationCount = pendingCount);
      }
    } catch (e) {
      debugPrint("Gagal mengambil jumlah notifikasi: $e");
    }
  }

  Future<void> _ambilFotoDanAbsen() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScanScreen()),
    );
    if (res == true) {
      _fetchRiwayat();
    }
  }

  String get _positionLabel {
    final position = widget.userData['position'];
    if (position is Map) return position['name']?.toString() ?? 'Staff';
    if (position is String && position.isNotEmpty) return position;
    return 'Junior Staff IT';
  }

  String get _departmentLabel {
    final department = widget.userData['department'];
    if (department is Map) return department['name']?.toString() ?? '';
    if (department is String && department.isNotEmpty) return department;
    return '';
  }

  List<_NavItem> get _navItems {
    if (_canApprove) {
      return [
        _NavItem(icon: Icons.face_outlined, logicIndex: 0),
        _NavItem(icon: Icons.access_time, logicIndex: 1),
        _NavItem(icon: Icons.description_outlined, logicIndex: 2),
        _NavItem(
          icon: Icons.notifications_outlined,
          logicIndex: 3,
          showBadge: true,
        ),
        _NavItem(icon: Icons.person_outline, logicIndex: 4),
      ];
    } else {
      return [
        _NavItem(icon: Icons.face_outlined, logicIndex: 0),
        _NavItem(icon: Icons.access_time, logicIndex: 1),
        _NavItem(icon: Icons.description_outlined, logicIndex: 2),
        _NavItem(icon: Icons.person_outline, logicIndex: 3),
      ];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD UTAMA UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A2246),
                  Color(0xFF1D4461),
                  Color(0xFF90CAF9),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 25,
                      vertical: 20,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 75,
                          height: 75,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E0E0),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildCompanyLogo(),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                companyName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                widget.userData['name']?.toString() ??
                                    'Pengguna',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _departmentLabel.isNotEmpty
                                    ? '$_positionLabel • $_departmentLabel'
                                    : _positionLabel,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          if (!_checkingFaceStatus)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: _buildFaceRegistrationBanner(),
                            ),
                          const SizedBox(height: 40),
                          _buildCameraButton(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          _buildDraggableRiwayatSheet(),

          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
        ],
      ),
    );
  }

  Widget _buildCompanyLogo() {
    if (companyLogo.isEmpty) {
      debugPrint('⚠️ companyLogo kosong, tampilkan icon default');
      return const Icon(Icons.business, color: Color(0xFF0A2246), size: 35);
    }

    debugPrint('🖼️ Mencoba load logo dari: $companyLogo');

    return Image.network(
      companyLogo,
      fit: BoxFit.cover,
      headers: const {'Accept': 'image/*'},
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Gagal load logo: $error | URL: $companyLogo');
        return const Icon(Icons.business, color: Color(0xFF0A2246), size: 35);
      },
    );
  }

  Widget _buildDraggableRiwayatSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.32,
      maxChildSize: 0.88,
      snap: true,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF9BB7D4).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(45),
              topRight: Radius.circular(45),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 60,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 15),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Builder(
                      builder: (ctx) => GestureDetector(
                        onTap: () async {
                          final RenderBox button =
                              ctx.findRenderObject() as RenderBox;
                          final RenderBox overlay =
                              Navigator.of(
                                    ctx,
                                  ).overlay!.context.findRenderObject()
                                  as RenderBox;
                          final RelativeRect position = RelativeRect.fromRect(
                            Rect.fromPoints(
                              button.localToGlobal(
                                Offset.zero,
                                ancestor: overlay,
                              ),
                              button.localToGlobal(
                                button.size.bottomRight(Offset.zero),
                                ancestor: overlay,
                              ),
                            ),
                            Offset.zero & overlay.size,
                          );

                          final selected = await showMenu<String>(
                            context: ctx,
                            position: position,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            color: const Color(0xFF0A2246),
                            items: [
                              PopupMenuItem(
                                value: 'absensi',
                                child: Row(
                                  children: const [
                                    Icon(
                                      Icons.access_time,
                                      color: Colors.white,
                                      size: 18,
                                    ),
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
                                    Icon(
                                      Icons.description_outlined,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
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

                          if (!mounted) return;
                          if (selected == 'absensi') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RiwayatScreen(),
                              ),
                            );
                          } else if (selected == 'pengajuan') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LeaveHistoryScreen(),
                              ),
                            );
                          }
                        },
                        child: Row(
                          children: const [
                            Text(
                              "Riwayat Absensi",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F2C52),
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF0F2C52),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: Color(0xFF0F2C52),
                        size: 20,
                      ),
                      onPressed: _fetchRiwayat,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Expanded(child: _buildRiwayatList(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFaceRegistrationBanner() {
    if (_isFaceRegistered) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 30),
            SizedBox(width: 12),
            Text(
              "Wajah Berhasil Terdaftar!",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Wajah Belum Terdaftar!",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Daftarkan wajah terlebih dahulu",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _goToFaceRegistration,
            icon: const Icon(
              Icons.arrow_circle_right_outlined,
              color: Color(0xFF0A2246),
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraButton() {
    return Column(
      children: [
        GestureDetector(
          onTap: _ambilFotoDanAbsen,
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF9BB7D4).withOpacity(0.3),
              border: Border.all(
                color: const Color(0xFFC2D3E4).withOpacity(0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF020E31),
                ),
                child: const Icon(
                  Icons.face_outlined,
                  color: Colors.white,
                  size: 65,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          "Tap untuk Absen",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _buildRiwayatList(ScrollController scrollController) {
    if (riwayat.isEmpty) {
      return SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              "Belum ada riwayat absensi",
              style: TextStyle(color: Colors.black45),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(left: 25, right: 25, bottom: 100),
      itemCount: riwayat.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = riwayat[index];

        final dynamic isLateRaw = item['is_late'];
        final bool isLate =
            isLateRaw == true ||
            isLateRaw == 1 ||
            isLateRaw == '1' ||
            isLateRaw == 'true' ||
            isLateRaw.toString().toLowerCase() == 'true' ||
            isLateRaw.toString() == '1';

        final bool isTepat = !isLate;

        debugPrint('📌 is_late raw value: $isLateRaw | isTepat: $isTepat');

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RiwayatScreen()),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isTepat ? Colors.green : Colors.red,
                      width: 4,
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE0E0E0),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildAttendancePhoto(item['pic_in']),
                  ),
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${item['tanggal']}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1D4461),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "${item['office_name']}",
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // const Text(
                //   "Detail",
                //   style: TextStyle(
                //     color: Color(0xFF1D4461),
                //     fontWeight: FontWeight.bold,
                //     fontSize: 13,
                //   ),
                // ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttendancePhoto(String? picUrl) {
    if (picUrl == null || picUrl.isEmpty) {
      return const Icon(Icons.person, color: Color(0xFF0A2246), size: 24);
    }

    return Image.network(
      picUrl,
      fit: BoxFit.cover,
      headers: const {'Accept': 'image/*'},
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.person, color: Color(0xFF0A2246), size: 24);
      },
    );
  }

  Widget _buildBottomNav() {
    final items = _navItems;
    return Container(
      height: 75,
      margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF90CAF9).withOpacity(0.85),
        borderRadius: BorderRadius.circular(35),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) => _buildNavItem(item)).toList(),
      ),
    );
  }

  Widget _buildNavItem(_NavItem item) {
    final bool isSelected = _currentIndex == item.logicIndex;
    return GestureDetector(
      onTap: () => _handleBottomNavTap(item.logicIndex),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF020E31) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.icon,
              color: isSelected
                  ? Colors.white
                  : const Color(0xFF020E31).withOpacity(0.7),
              size: 26,
            ),
          ),
          if (item.showBadge && _notificationCount > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _notificationCount > 9 ? '9+' : '$_notificationCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleBottomNavTap(int logicIndex) async {
    if (logicIndex == 0) {
      setState(() => _currentIndex = 0);
      return;
    }

    Widget page;
    if (_canApprove) {
      switch (logicIndex) {
        case 1:
          page = AbsenPulangScreen(userData: widget.userData);
          break;
        case 2:
          page = const LeaveRequestScreen();
          break;
        case 3:
          page = const ApprovalPengajuanPage();
          break;
        case 4:
          page = ProfileScreen(userData: _profileSafeUserData);
          break;
        default:
          return;
      }
    } else {
      switch (logicIndex) {
        case 1:
          page = AbsenPulangScreen(userData: widget.userData);
          break;
        case 2:
          page = const LeaveRequestScreen();
          break;
        case 3:
          page = ProfileScreen(userData: _profileSafeUserData);
          break;
        default:
          return;
      }
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );

    if (mounted) {
      setState(() => _currentIndex = 0);
      if (_canApprove) {
        _fetchNotificationCount();
      }
    }
  }
}

class _NavItem {
  final IconData icon;
  final int logicIndex;
  final bool showBadge;
  _NavItem({
    required this.icon,
    required this.logicIndex,
    this.showBadge = false,
  });
}
