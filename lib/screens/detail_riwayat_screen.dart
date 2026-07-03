import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class DetailRiwayatScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const DetailRiwayatScreen({super.key, required this.data});

  static const Color _darkBlue = Color(0xFF0A2246);
  static const Color _midBlue = Color(0xFF1D4461);
  static const Color _lightBlue = Color(0xFF90CAF9);

  static const List<String> _dayNames = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
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

  bool get _hasCheckout {
    final t = data['time_out']?.toString() ?? '';
    return t.isNotEmpty && t != 'null';
  }

  String _val(String key, [String fallback = '-']) {
    final v = data[key]?.toString();
    if (v == null || v.isEmpty || v == 'null') return fallback;
    return v;
  }

  bool get _isLate {
    final v = data['is_late'];
    return v == true || v?.toString() == '1';
  }

  String get _dateLabel {
    final d = DateTime.tryParse(_val('date', _val('tanggal', '')));
    if (d == null) return _val('date', _val('tanggal', '-'));
    return '${_dayNames[d.weekday - 1]}, '
        '${d.day.toString().padLeft(2, '0')} '
        '${_monthShort[d.month - 1]} '
        '${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final latIn = _val('lat_in', _val('latitude', '0.0'));
    final lngIn = _val('long_in', _val('longitude', '0.0'));
    final latOut = _val('lat_out', '0.0');
    final lngOut = _val('long_out', '0.0');

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
              // ── Header ──
              Padding(
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
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dateLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          _val('office_name', 'Kantor'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Body ──
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                    child: Column(
                      children: [
                        _buildCard(
                          title: 'Absen Masuk',
                          time: _val('time_in', '--:--'),
                          statusLabel: _isLate ? 'Terlambat' : 'Tepat Waktu',
                          statusColor: _isLate ? Colors.red : Colors.green,
                          lat: latIn,
                          lng: lngIn,
                          imageUrl: _val('pic_in', _val('image_url', '')),
                          accentColor: Colors.blue,
                          isEmpty: false,
                        ),
                        const SizedBox(height: 14),
                        _buildCard(
                          title: 'Absen Pulang',
                          time: _hasCheckout ? _val('time_out', '--:--') : '-',
                          statusLabel: _hasCheckout
                              ? 'Selesai'
                              : 'Belum Checkout',
                          statusColor: _hasCheckout
                              ? Colors.green
                              : Colors.orange,
                          lat: latOut,
                          lng: lngOut,
                          imageUrl: _val('pic_out', ''),
                          accentColor: _hasCheckout
                              ? Colors.green
                              : Colors.orange,
                          isEmpty: !_hasCheckout,
                        ),
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

  Widget _buildCard({
    required String title,
    required String time,
    required String statusLabel,
    required Color statusColor,
    required String lat,
    required String lng,
    required String imageUrl,
    required Color accentColor,
    required bool isEmpty,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  title.contains('Pulang') ? Icons.logout : Icons.login,
                  color: accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _darkBlue,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (!isEmpty) ...[
            // 1. PETA GPS
            _MapView(lat: lat, lng: lng, accentColor: accentColor),

            const SizedBox(height: 12),

            // 2. INFO
            _buildInfoRow(
              icon: Icons.location_on,
              color: Colors.red.shade400,
              text: _val('office_name', 'Kantor'),
            ),
            _buildInfoRow(
              icon: Icons.gps_fixed,
              color: Colors.blue.shade400,
              text: '$lat, $lng',
            ),
            _buildInfoRow(
              icon: Icons.access_time,
              color: _darkBlue,
              text: time == '--:--' ? time : '$time WIB',
            ),

            const SizedBox(height: 14),

            // 3. FOTO WAJAH (kecil, di bawah)
            _FotoWajahRow(imageUrl: imageUrl, accentColor: accentColor),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade600,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Data absen pulang akan muncul setelah checkout.',
                      style: TextStyle(color: Colors.orange, fontSize: 13),
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

  Widget _buildInfoRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: _midBlue),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _MapView — fetch tile OSM via http (pakai Authorization header agar tidak
// diblokir) lalu tampilkan dengan Image.memory
// ══════════════════════════════════════════════════════════════════════════════
class _MapView extends StatefulWidget {
  final String lat;
  final String lng;
  final Color accentColor;

  const _MapView({
    required this.lat,
    required this.lng,
    required this.accentColor,
  });

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  // Kita ambil 3x3 grid tile dan susun sebagai peta
  // Tapi untuk simplisitas, kita ambil 1 tile center + 8 surrounding
  // lalu tampilkan sebagai grid 3x3

  static const int _zoom = 16;

  bool _loading = true;
  bool _error = false;

  // 3x3 grid: [row][col] = bytes tile
  final List<List<Uint8List?>> _tiles = List.generate(
    3,
    (_) => List.filled(3, null),
  );

  bool get _valid {
    final la = double.tryParse(widget.lat);
    final lo = double.tryParse(widget.lng);
    return la != null && lo != null && la != 0.0 && lo != 0.0;
  }

  // Konversi lat/lng ke tile x,y pada zoom tertentu
  (int x, int y) _latLngToTile(double lat, double lng, int zoom) {
    final n = math.pow(2, zoom).toInt();
    final x = ((lng + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
    final latRad = lat * math.pi / 180.0;
    final y =
        ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
                2.0 *
                n)
            .floor()
            .clamp(0, n - 1);
    return (x, y);
  }

  Future<Uint8List?> _fetchTile(int x, int y) async {
    // Pilih subdomain a/b/c secara bergantian
    final sub = ['a', 'b', 'c'][x % 3];
    final url = 'https://$sub.tile.openstreetmap.org/$_zoom/$x/$y.png';
    try {
      final res = await http
          .get(
            Uri.parse(url),
            headers: {
              // OSM mewajibkan User-Agent yang valid
              'User-Agent': 'AbsensiApp/1.0 (flutter; contact@yourdomain.com)',
              'Accept': 'image/png',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_valid)
      _loadTiles();
    else
      setState(() {
        _loading = false;
        _error = true;
      });
  }

  Future<void> _loadTiles() async {
    final la = double.parse(widget.lat);
    final lo = double.parse(widget.lng);
    final (cx, cy) = _latLngToTile(la, lo, _zoom);

    // Fetch 3x3 grid secara paralel
    final futures = <Future<void>>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final tx = cx + col - 1;
        final ty = cy + row - 1;
        futures.add(
          _fetchTile(tx, ty).then((bytes) {
            if (mounted) _tiles[row][col] = bytes;
          }),
        );
      }
    }
    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _loading = false;
        // error jika semua tile null
        _error = _tiles.every((row) => row.every((t) => t == null));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.map_outlined, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'Lokasi GPS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: _loading
                ? Container(
                    color: const Color(0xFFE8EDF2),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 8),
                          Text(
                            'Memuat peta...',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                : _error
                ? _buildFallback()
                : _buildMapGrid(),
          ),
        ),
      ],
    );
  }

  Widget _buildMapGrid() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Grid 3x3 tile
        Column(
          children: List.generate(
            3,
            (row) => Expanded(
              child: Row(
                children: List.generate(3, (col) {
                  final bytes = _tiles[row][col];
                  if (bytes == null) {
                    return Expanded(
                      child: Container(color: const Color(0xFFD0DCE8)),
                    );
                  }
                  return Expanded(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  );
                }),
              ),
            ),
          ),
        ),

        // Pin di tengah
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_pin,
                color: widget.accentColor,
                size: 42,
                shadows: const [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              Container(
                width: 10,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ),
        ),

        // Label koordinat pojok bawah kiri
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${widget.lat}, ${widget.lng}',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),

        // Credit OSM pojok bawah kanan
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '© OpenStreetMap',
              style: TextStyle(fontSize: 9, color: Colors.black54),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFFE8EDF2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off, color: Colors.grey.shade400, size: 36),
          const SizedBox(height: 6),
          Text(
            'Gagal memuat peta',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.lat}, ${widget.lng}',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _FotoWajahRow — thumbnail kecil kiri, info + tombol lihat foto kanan
// ══════════════════════════════════════════════════════════════════════════════
class _FotoWajahRow extends StatelessWidget {
  final String imageUrl;
  final Color accentColor;

  const _FotoWajahRow({required this.imageUrl, required this.accentColor});

  bool get _hasImage => imageUrl.isNotEmpty && imageUrl != '-';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Thumbnail kecil
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 72,
              child: _hasImage
                  ? _AuthorizedImage(url: imageUrl)
                  : Container(
                      color: const Color(0xFFE0E6EF),
                      child: Icon(
                        Icons.person,
                        color: Colors.grey.shade400,
                        size: 32,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Info kanan
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.face_outlined,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Foto Wajah',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _hasImage ? 'Foto terverifikasi' : 'Foto tidak tersedia',
                  style: TextStyle(
                    fontSize: 12,
                    color: _hasImage
                        ? Colors.green.shade600
                        : Colors.grey.shade500,
                  ),
                ),
                if (_hasImage) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showFull(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accentColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        'Lihat Foto',
                        style: TextStyle(
                          fontSize: 11,
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFull(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: _AuthorizedImage(url: imageUrl),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
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

// ══════════════════════════════════════════════════════════════════════════════
// _AuthorizedImage — fetch gambar dengan Bearer token
// ══════════════════════════════════════════════════════════════════════════════
class _AuthorizedImage extends StatefulWidget {
  final String url;
  const _AuthorizedImage({required this.url});

  @override
  State<_AuthorizedImage> createState() => _AuthorizedImageState();
}

class _AuthorizedImageState extends State<_AuthorizedImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.url.isEmpty || widget.url == '-') {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      final res = await http.get(
        Uri.parse(widget.url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Accept': 'image/*',
        },
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _bytes = res.bodyBytes;
          _loading = false;
        });
      } else {
        if (mounted)
          setState(() {
            _loading = false;
            _error = true;
          });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error || _bytes == null) {
      return Container(
        color: const Color(0xFFE0E6EF),
        child: Icon(Icons.broken_image, color: Colors.grey.shade400, size: 32),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
