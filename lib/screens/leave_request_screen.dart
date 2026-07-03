import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/constants.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionController = TextEditingController();
  final List<String> _leaveTypes = ['Cuti', 'Izin', 'Sakit'];
  String _selectedType = 'Cuti';
  DateTime? _startDate;
  DateTime? _endDate;
  XFile? _attachment;
  bool _isSubmitting = false;

  // Penyelarasan Tema Warna sesuai UI Dashboard & Riwayat
  static const Color _darkBlue = Color(0xFF0A2246);
  static const Color _midBlue = Color(0xFF1D4461);
  static const Color _lightBlue = Color(0xFF90CAF9);
  static const Color _btnNavDark = Color(0xFF001140);

  bool get _requiresAttachment => _selectedType != 'Cuti';

  Future<void> _pickDate({required bool isStart}) async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = isStart
        ? (_startDate ?? now)
        : (_endDate ?? (_startDate ?? now));
    final DateTime firstDate = DateTime(now.year - 1);
    final DateTime lastDate = DateTime(now.year + 2);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: const ColorScheme.light(primary: _darkBlue)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = picked;
          }
        } else {
          _endDate = picked;
          if (_startDate != null && _endDate!.isBefore(_startDate!)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _pickAttachment() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (file != null) {
      setState(() {
        _attachment = file;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return "";
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih tanggal mulai dan selesai terlebih dahulu.'),
        ),
      );
      return;
    }

    if (_requiresAttachment && _attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lampiran wajib untuk jenis Sakit atau Izin.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('token');
      if (token == null)
        throw Exception('Token tidak ditemukan. Silakan login ulang.');

      final uri = Uri.parse('${AppConstants.baseUrl}/leave');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      request.fields['type'] = _selectedType;
      request.fields['start_date'] = _startDate!
          .toIso8601String()
          .split('T')
          .first;
      request.fields['end_date'] = _endDate!.toIso8601String().split('T').first;
      request.fields['reason'] = _descriptionController.text.trim();

      if (_attachment != null) {
        final file = File(_attachment!.path);
        request.files.add(
          await http.MultipartFile.fromPath('image', file.path),
        );
      }

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (streamedResponse.statusCode == 200 ||
          streamedResponse.statusCode == 201) {
        if (!mounted) return;
        setState(() {
          _selectedType = 'Cuti';
          _startDate = null;
          _endDate = null;
          _descriptionController.clear();
          _attachment = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengajuan izin berhasil dikirim.')),
        );
      } else {
        final message = responseData['message'] ?? 'Gagal mengirim pengajuan.';
        throw Exception(message);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
              // Header melengkung tipis di bagian atas
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Card pill transparan di belakang judul, melebar penuh
                    // sama seperti di halaman Absen Pulang.
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
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
                          'Pengajuan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Form Konten Utama
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Baris Pilihan Type (Cuti, Izin, Sakit) melingkar sesuai UI asli
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: _leaveTypes.map((type) {
                            final isSelected = _selectedType == type;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedType = type),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withOpacity(0.25)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(25),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      type,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),

                        // Input Tanggal Mulai & Tanggal Selesai berdampingan
                        Row(
                          children: [
                            Expanded(
                              child: _buildInputField(
                                hint: 'Tanggal Mulai',
                                value: _formatDate(_startDate),
                                icon: Icons.calendar_today,
                                onTap: () => _pickDate(isStart: true),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInputField(
                                hint: 'Tanggal Selesai',
                                value: _formatDate(_endDate),
                                icon: Icons.calendar_today,
                                onTap: () => _pickDate(isStart: false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Input Keterangan / Alasan
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _descriptionController,
                            maxLines: 4,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Keterangan',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                              contentPadding: const EdgeInsets.all(16),
                              border: InputBorder.none,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Keterangan wajib diisi.';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Input Upload Lampiran Bukti
                        _buildInputField(
                          hint: _attachment != null
                              ? _attachment!.name
                              : 'Upload Lampiran Format: JPG, PNG, atau PDF',
                          value: '',
                          icon: Icons.cloud_upload_outlined,
                          onTap: _pickAttachment,
                          isAttachmentField: true,
                        ),
                        const SizedBox(height: 36),

                        // Tombol "Ajukan" Utama Biru Dongker Tebal
                        Center(
                          child: SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submitRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _btnNavDark,
                                elevation: 5,
                                shadowColor: Colors.black54,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              child: _isSubmitting
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      'Ajukan',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
        ),
      ),
    );
  }

  // Helper Widget untuk Form Fields agar putih bersih + shadow soft sesuai desain UI
  Widget _buildInputField({
    required String hint,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    bool isAttachmentField = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isNotEmpty ? value : hint,
                style: TextStyle(
                  color: value.isNotEmpty || isAttachmentField
                      ? Colors.black87
                      : Colors.grey.shade400,
                  fontSize: 13,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Icon(icon, color: _midBlue, size: 20),
          ],
        ),
      ),
    );
  }
}