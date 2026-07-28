import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'login_page.dart';
import '../services/verification_log_service.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProfileScreen({super.key, required this.userData});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final VerificationLogService _logService = VerificationLogService();
  bool _isFaceRegistered = false;
  String? _registeredDate;
  String? _profileImagePath;
  String? _profileImageUrl;
  bool _isUploadingPhoto = false;

  // ─── Warna tema ────────────────────────────────────────────────────────────
  static const Color _bgTop = Color(0xFF0A2246);
  static const Color _bgMid = Color(0xFF1D4461);
  static const Color _bgBot = Color(0xFF90CAF9);

  // Teks di atas gradient gelap (nama, subtitle, judul section)
  static const Color _textPri = Colors.white;
  static const Color _textMut = Color(0xFFE8F0F8);

  // Teks di dalam card terang (Informasi & Registrasi wajah)
  static const Color _cardTextPri = Color(0xFF0A2246); // navy gelap
  static const Color _cardTextMut = Color(0xFF3A5A78); // navy medium (label)
  static const Color _cardIconColor = Color(0xFF0A2246);

  static const Color _divider = Color(0xFF1D4461);

  String get _profilePhotoKey {
    final id = widget.userData['id']?.toString() ?? 'current';
    return 'profile_photo_path_$id';
  }

  String get _userId => widget.userData['id']?.toString() ?? 'default';
  String get _keyRegistered => 'face_registered_$_userId';
  String get _keyDate => 'face_registered_date_$_userId';

  String get _displayName =>
      widget.userData['name']?.toString() ?? 'Admin Proyek';

  String get _initials {
    final words = _displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'U';
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _loadFaceRegistrationStatus();
    _loadProfilePhoto();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGIKA
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadFaceRegistrationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey);
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/face-embedding'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;
      setState(() {
        _isFaceRegistered = response.statusCode == 200;
      });

      // Ambil tanggal dari cache lokal kalau ada (opsional, cuma buat tampilan)
      _registeredDate = prefs.getString(_keyDate);
    } catch (e) {
      debugPrint('Gagal cek status wajah di profile: $e');
    }
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final localPath = prefs.getString(_profilePhotoKey);
    final imageUrl = widget.userData['image_url']?.toString();

    if (!mounted) return;
    setState(() {
      _profileImagePath = localPath != null && File(localPath).existsSync()
          ? localPath
          : null;
      _profileImageUrl = imageUrl != null && imageUrl.isNotEmpty
          ? imageUrl
          : null;
    });
  }

  ImageProvider? get _profileImageProvider {
    if (_profileImagePath != null) return FileImage(File(_profileImagePath!));
    if (_profileImageUrl != null) return NetworkImage(_profileImageUrl!);
    return null;
  }

  Future<void> _showPhotoActions() async {
    if (_isUploadingPhoto) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final hasPhoto = _profileImageProvider != null;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Ambil foto'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Pilih dari galeri'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadPhoto(ImageSource.gallery);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Hapus foto',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteProfilePhoto();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (pickedFile == null) return;
    await _syncProfilePhoto(file: pickedFile);
  }

  Future<void> _deleteProfilePhoto() async {
    await _syncProfilePhoto(removeImage: true);
  }

  Future<void> _syncProfilePhoto({
    XFile? file,
    bool removeImage = false,
  }) async {
    setState(() => _isUploadingPhoto = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      if (token == null || token.isEmpty) {
        throw Exception('Token tidak ditemukan. Silakan login ulang.');
      }

      http.StreamedResponse response;
      String responseBody;

      if (removeImage) {
        final request = http.Request(
          'DELETE',
          Uri.parse('${AppConstants.baseUrl}/profile/photo'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'application/json';
        response = await request.send();
        responseBody = await response.stream.bytesToString();
      } else {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConstants.baseUrl}/profile/photo'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'application/json';
        request.fields['_method'] = 'PUT';
        if (file != null) {
          request.files.add(
            await http.MultipartFile.fromPath('image', file.path),
          );
        }
        response = await request.send();
        responseBody = await response.stream.bytesToString();
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        String message = 'Gagal memperbarui foto profil.';
        if (responseBody.isNotEmpty) {
          try {
            final data = jsonDecode(responseBody);
            if (data is Map && data['message'] != null) {
              message = data['message'].toString();
            }
          } catch (_) {}
        }
        throw Exception(message);
      }

      String? newImageUrl;
      if (responseBody.isNotEmpty) {
        try {
          final data = jsonDecode(responseBody);
          if (data is Map) {
            newImageUrl =
                data['data']?['image_url']?.toString() ??
                data['image_url']?.toString();
          }
        } catch (_) {}
      }

      if (removeImage) {
        await prefs.remove(_profilePhotoKey);
        widget.userData['image_url'] = null;
      } else if (file != null) {
        await prefs.setString(_profilePhotoKey, file.path);
        widget.userData['image_url'] = newImageUrl;
      }

      if (!mounted) return;
      setState(() {
        _profileImagePath = removeImage ? null : file?.path;
        _profileImageUrl = removeImage
            ? null
            : (newImageUrl?.isNotEmpty == true
                  ? newImageUrl
                  : _profileImageUrl);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: removeImage ? Colors.orange : Colors.green,
          content: Text(
            removeImage
                ? 'Foto profil berhasil dihapus.'
                : 'Foto profil berhasil diperbarui.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar'),
        content: const Text('Apakah kamu yakin ingin keluar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGET HELPER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProfileAvatar() {
    final imageProvider = _profileImageProvider;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: const Color(0xFF1D4461),
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  _initials,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                )
              : null,
        ),
        if (_isUploadingPhoto)
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: -2,
          bottom: -2,
          child: GestureDetector(
            onTap: _showPhotoActions,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF1D4461),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0A2246), width: 2),
              ),
              child: const Icon(Icons.edit, color: Colors.white70, size: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4461).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _cardIconColor, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _cardTextMut,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _cardTextPri,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: _divider.withOpacity(0.2),
            indent: 66,
            endIndent: 16,
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final String perusahaan =
        widget.userData['company']?['name']?.toString() ??
        widget.userData['company_name']?.toString() ??
        widget.userData['tenant']?['name']?.toString() ??
        'PT. Surya Gaya Dharmaputra';

    final String kantor =
        widget.userData['office']?['name']?.toString() ?? 'Kantor Pusat';

    final String departemen =
        widget.userData['department']?['name']?.toString() ?? '-';

    final String jabatan =
        widget.userData['position']?['name']?.toString() ?? '-';

    final String deptJabatan = [
      departemen,
      jabatan,
    ].where((s) => s != '-').join(' - ');

    final String email = widget.userData['email']?.toString() ?? '-';

    final String nik = widget.userData['nik']?.toString() ?? '-';

    final String subTitle =
        widget.userData['position']?['name']?.toString() ?? 'Junior Staff IT';

    return Scaffold(
      backgroundColor: _bgTop,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A2246), Color(0xFF1D4461), Color(0xFF90CAF9)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D4461).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      tooltip: 'Keluar',
                      onPressed: _handleLogout,
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D4461).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.logout,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              _buildProfileAvatar(),
              const SizedBox(height: 14),
              Text(
                _displayName,
                style: const TextStyle(
                  color: _textPri,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subTitle,
                style: const TextStyle(color: _textMut, fontSize: 13),
              ),
              const SizedBox(height: 24),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 10),
                        child: Text(
                          'Informasi',
                          style: TextStyle(
                            color: _textPri,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              icon: Icons.business_outlined,
                              label: 'Perusahaan',
                              value: perusahaan,
                            ),
                            _buildInfoRow(
                              icon: Icons.location_city_outlined,
                              label: 'Kantor',
                              value: kantor,
                            ),
                            _buildInfoRow(
                              icon: Icons.badge_outlined,
                              label: 'Departemen · Jabatan',
                              value: deptJabatan.isNotEmpty ? deptJabatan : '-',
                            ),
                            _buildInfoRow(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              value: email,
                            ),
                            _buildInfoRow(
                              icon: Icons.credit_card_outlined,
                              label: 'NIK',
                              value: nik,
                              isLast: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF1D4461,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.face_retouching_natural,
                                color: _cardIconColor,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Registrasi wajah',
                                    style: TextStyle(
                                      color: _cardTextPri,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isFaceRegistered
                                        ? 'Sudah terdaftar'
                                        : 'Belum terdaftar',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _isFaceRegistered
                                          ? const Color(0xFF1E8E5A)
                                          : const Color(0xFF9C6A1E),
                                    ),
                                  ),
                                  if (_isFaceRegistered &&
                                      _registeredDate != null)
                                    Text(
                                      'Terdaftar: ${_formatDate(DateTime.parse(_registeredDate!))}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _cardTextMut,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _isFaceRegistered
                                    ? const Color(0xFFDDF3E7)
                                    : const Color(0xFFF6E6CE),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _isFaceRegistered ? 'Aktif' : 'Daftar',
                                style: TextStyle(
                                  color: _isFaceRegistered
                                      ? const Color(0xFF1E8E5A)
                                      : const Color(0xFF9C6A1E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Export Log Pengujian (Debug)',
                                style: TextStyle(
                                  color: _cardTextPri,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.upload_file,
                                color: _cardIconColor,
                              ),
                              tooltip: 'Export log CSV',
                              onPressed: () async {
                                await _logService.exportLog();
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/${date.year}";
  }
}
