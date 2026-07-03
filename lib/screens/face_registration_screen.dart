import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/face_recognition_service.dart';
import '../utils/constants.dart';
import '../utils/face_crop_utils.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  final FaceRecognitionService _faceService = FaceRecognitionService();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  CameraController? _controller;
  File? _image;
  bool _isProcessing = false;
  bool _isModelLoaded = false;
  bool _isCameraInitialized = false;
  bool _isBusy = false;
  bool _faceDetected = false;
  bool _autoCaptureTriggered = false;
  int _currentStep = 1;
  int _stableFaceFrames = 0;
  double _scanProgress = 0;
  DateTime? _registeredAt;

  String _userId = 'default';

  // ─── Warna tema ───────────────────────────────────────────────────────────
  static const Color _bgColor = Color(0xFF0D1B2A);
  // static const Color _cardColor = Color(0xFF162233);
  static const Color _accentColor = Color(0xFF1A6FC4);
  static const Color _activeStep = Color(0xFF1A6FC4);
  static const Color _inactiveStep = Color(0xFF2A3A4A);
  static const Color _textPrimary = Colors.white;
  static const Color _textMuted = Color(0xFF8899AA);
  static const Color _btnColor = Color(0xFF14243A);
  static const Color _btnText = Color(0xFF7799BB);

  @override
  void initState() {
    super.initState();
    _loadModel();
    _initUserId();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGIKA — tidak ada yang diubah dari kode asli
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(AppConstants.userKey);

    if (userJson != null && userJson.isNotEmpty) {
      try {
        final map = jsonDecode(userJson) as Map<String, dynamic>;
        final id = map['id']?.toString() ?? '';
        if (id.isNotEmpty) _userId = id;
      } catch (e) {
        debugPrint('Gagal parse user data: $e');
      }
    }

    Future<void> _checkServerEmbedding() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(AppConstants.tokenKey);

        final response = await http.get(
          Uri.parse('${AppConstants.baseUrl}/face-embedding'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 404) {
          await prefs.remove(_keyRegistered);
          await prefs.remove(_keyImagePath);
          await prefs.remove(_keyDate);
          if (mounted) setState(() => _currentStep = 1);
        }
      } catch (e) {
        debugPrint('Error check server embedding: $e');
      }
    }

    debugPrint('Face registration userId: $_userId');
    await _loadSavedFace();
    await _checkServerEmbedding();
  }

  String get _keyRegistered => 'face_registered_$_userId';
  String get _keyImagePath => 'face_image_path_$_userId';
  String get _keyDate => 'face_registered_date_$_userId';

  Future<void> _loadSavedFace() async {
    final prefs = await SharedPreferences.getInstance();
    final isRegistered = prefs.getBool(_keyRegistered) ?? false;
    if (!isRegistered) return;

    final savedPath = prefs.getString(_keyImagePath);
    final savedDate = prefs.getString(_keyDate);

    if (savedPath != null) {
      final file = File(savedPath);
      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _image = file;
            _currentStep = 3;
            _registeredAt = savedDate != null
                ? DateTime.tryParse(savedDate)
                : null;
          });
        }
      } else {
        await prefs.remove(_keyRegistered);
        await prefs.remove(_keyImagePath);
        await prefs.remove(_keyDate);
      }
    }
  }

  Future<void> _loadModel() async {
    try {
      await _faceService.loadModel();
      if (mounted) setState(() => _isModelLoaded = true);
    } catch (e) {
      _showMessage("Gagal memuat model: $e", Colors.red);
    }
  }

  Future<void> _startFaceScan() async {
    final prefs = await SharedPreferences.getInstance();
    final isRegistered = prefs.getBool(_keyRegistered) ?? false;
    if (isRegistered) {
      _showMessage(
        "Wajah sudah terdaftar dan tidak dapat diubah.",
        Colors.orange,
      );
      return;
    }

    setState(() {
      _currentStep = 2;
      _isProcessing = false;
      _faceDetected = false;
      _autoCaptureTriggered = false;
      _stableFaceFrames = 0;
      _scanProgress = 0;
      _image = null;
    });

    await _initLiveCamera();
  }

  Future<void> _initLiveCamera() async {
    if (_controller != null && _controller!.value.isInitialized) return;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showMessage("Kamera tidak ditemukan.", Colors.red);
        return;
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();
      await _controller!.startImageStream((CameraImage image) {
        if (_isBusy || _isProcessing || _autoCaptureTriggered) return;
        _isBusy = true;
        _detectFace(image);
      });

      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      _showMessage("Gagal membuka kamera: $e", Colors.red);
    }
  }

  Future<void> _detectFace(CameraImage image) async {
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    final bytes = allBytes.done().buffer.asUint8List();
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: InputImageRotation.rotation270deg,
      format:
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);

    try {
      final faces = await _faceDetector.processImage(inputImage);
      final hasFace = faces.isNotEmpty;

      if (mounted) {
        setState(() {
          _faceDetected = hasFace;
          _stableFaceFrames = hasFace ? _stableFaceFrames + 1 : 0;
          _scanProgress = (_stableFaceFrames / 5).clamp(0, 1).toDouble();
        });
      }

      if (hasFace &&
          _stableFaceFrames >= 5 &&
          !_isProcessing &&
          !_autoCaptureTriggered) {
        _autoCaptureTriggered = true;
        Future.microtask(_captureRegistrationPhoto);
      }
    } catch (e) {
      debugPrint("Error deteksi wajah registrasi: $e");
    } finally {
      _isBusy = false;
    }
  }

  Future<String> _saveImagePermanently(String tempPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final faceDir = Directory('${appDir.path}/face_data/$_userId');

    if (!await faceDir.exists()) {
      await faceDir.create(recursive: true);
    }

    final permanentPath = '${faceDir.path}/face_photo.jpg';
    final tempFile = File(tempPath);
    await tempFile.copy(permanentPath);

    return permanentPath;
  }

  Future<void> _captureRegistrationPhoto() async {
    if (_controller == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      await Future.delayed(const Duration(milliseconds: 500));

      if (_controller == null || !_controller!.value.isInitialized) return;

      final capturedImage = await _controller!.takePicture();

      // ── Crop wajah dari foto hasil takePicture sebelum diproses ──
      final croppedFace = await FaceCropUtils.detectAndCropFace(
        imageFile: File(capturedImage.path),
        faceDetector: _faceDetector,
      );

      if (croppedFace == null) {
        _autoCaptureTriggered = false;
        _stableFaceFrames = 0;
        _scanProgress = 0;
        await _restartImageStream();
        _showMessage(
          "Wajah tidak terdeteksi dengan jelas, coba lagi.",
          Colors.red,
        );
        return;
      }

      final permanentPath = await _saveImagePermanently(croppedFace.path);

      setState(() {
        _image = File(permanentPath);
        _scanProgress = 1;
      });

      final embedding = _faceService.predict(_image!);
      debugPrint(
        "Data wajah berhasil diambil: ${embedding.length} angka embedding",
      );

      await _sendEmbeddingToServer(embedding);

      await _controller?.dispose();
      _controller = null;
      _isCameraInitialized = false;

      final prefs = await SharedPreferences.getInstance();
      _registeredAt = DateTime.now();
      await prefs.setBool(_keyRegistered, true);
      await prefs.setString(_keyImagePath, permanentPath);
      await prefs.setString(_keyDate, _registeredAt!.toIso8601String());

      if (!mounted) return;
      setState(() => _currentStep = 3);
      _showMessage("Wajah berhasil didaftarkan!", Colors.green);
    } catch (e) {
      _autoCaptureTriggered = false;
      _stableFaceFrames = 0;
      _scanProgress = 0;
      await _restartImageStream();
      _showMessage("Gagal memproses wajah: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendEmbeddingToServer(List<double> embedding) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/face-enrollment'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'embedding': embedding}),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('Face embedding berhasil dikirim ke server');
      } else {
        debugPrint('Gagal kirim embedding: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error kirim embedding: $e');
    }
  }

  Future<void> _restartImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (!_controller!.value.isStreamingImages) {
      await _controller!.startImageStream((CameraImage image) {
        if (_isBusy || _isProcessing || _autoCaptureTriggered) return;
        _isBusy = true;
        _detectFace(image);
      });
    }
  }

  Future<void> _disposeCamera() async {
    if (_controller == null) return;
    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
    await _controller!.dispose();
    _controller = null;
    _isCameraInitialized = false;
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _backToDashboard() {
    Navigator.pop(context, true);
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGET HELPER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Step indicator dengan garis penghubung seperti di gambar referensi
  Widget _buildStepIndicator() {
    return Row(
      children: [
        _stepCircle(1, "Persiapan"),
        _stepLine(fromStep: 1),
        _stepCircle(2, "Scan"),
        _stepLine(fromStep: 2),
        _stepCircle(3, "Selesai"),
      ],
    );
  }

  Widget _stepCircle(int step, String label) {
    final bool isActive = _currentStep == step;
    final bool isDone = _currentStep > step;
    final Color circleBg = (isActive || isDone) ? _activeStep : _inactiveStep;

    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : Text(
                  step.toString(),
                  style: TextStyle(
                    color: isActive ? Colors.white : _textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: (isActive || isDone) ? _textPrimary : _textMuted,
          ),
        ),
      ],
    );
  }

  Widget _stepLine({required int fromStep}) {
    final bool passed = _currentStep > fromStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: passed ? _activeStep : _inactiveStep,
      ),
    );
  }

  Widget _buildTip(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: _accentColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                color: _textMuted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KONTEN PER STEP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1: Persiapan ─────────────────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Pastikan wajah terlihat jelas agar proses pemindaian berjalan optimal.",
          style: TextStyle(fontSize: 13, color: _textMuted, height: 1.5),
        ),
        const SizedBox(height: 20),
        _buildTip(
          "Lepaskan kacamata, topi, atau aksesori yang menutupi wajah.",
        ),
        _buildTip("Pilih lokasi dengan pencahayaan yang cukup dan merata."),
        _buildTip("Posisikan wajah tegak dan arahkan pandangan ke kamera."),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2030),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A3A4A)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Color(0xFFBB7744), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Registrasi wajah hanya bisa dilakukan 1 kali. "
                  "Hubungi Admin jika ingin registrasi ulang.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFBB7744),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isModelLoaded ? _startFaceScan : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isModelLoaded ? _accentColor : _inactiveStep,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text(
              _isModelLoaded ? "Mulai Scan" : "Memuat Model...",
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Scan ──────────────────────────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _faceDetected
              ? (_isProcessing
                    ? "Wajah terkunci. Sedang memproses..."
                    : "Bersiap scan wajah")
              : "Bersiap scan wajah",
          style: const TextStyle(fontSize: 13, color: _textMuted),
        ),
        const SizedBox(height: 28),

        // Oval kamera
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Kamera di dalam oval
              ClipRRect(
                borderRadius: BorderRadius.circular(200),
                child: SizedBox(
                  width: 230,
                  height: 290,
                  child: (_isCameraInitialized && _controller != null)
                      ? CameraPreview(_controller!)
                      : Container(color: const Color(0xFF1C2A3A)),
                ),
              ),
              // Border oval
              Container(
                width: 230,
                height: 290,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(200),
                  border: Border.all(
                    color: _faceDetected
                        ? const Color(0xFF44BB88)
                        : const Color(0xFF3A4A5A),
                    width: 2.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Progress bar
        if (_faceDetected && !_isProcessing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _scanProgress,
                backgroundColor: const Color(0xFF2A3A4A),
                color: const Color(0xFF44BB88),
                minHeight: 4,
              ),
            ),
          ),

        const SizedBox(height: 16),

        Text(
          _isProcessing
              ? "Sedang memproses..."
              : "Scan berjalan otomatis saat wajah stabil.",
          style: const TextStyle(fontSize: 12, color: _textMuted),
        ),

        const SizedBox(height: 28),

        // Tombol Batalkan
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isProcessing
                ? null
                : () async {
                    await _disposeCamera();
                    if (mounted) setState(() => _currentStep = 1);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: _btnColor,
              foregroundColor: _btnText,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text("Batalkan", style: TextStyle(fontSize: 15)),
          ),
        ),
      ],
    );
  }

  // ── Step 3: Selesai ───────────────────────────────────────────────────────
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          "Registrasi berhasil",
          style: TextStyle(fontSize: 16, color: _textMuted),
        ),
        const SizedBox(height: 28),

        // Foto wajah dalam oval
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(200),
            child: Image.file(
              _image!,
              width: 230,
              height: 290,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            width: 230,
            height: 290,
            decoration: BoxDecoration(
              color: const Color(0xFF1C2A3A),
              borderRadius: BorderRadius.circular(200),
              border: Border.all(color: const Color(0xFF3A4A5A), width: 2.5),
            ),
          ),

        const SizedBox(height: 24),

        Text(
          _registeredAt != null
              ? "Terdaftar pada ${_formatDate(_registeredAt!)}"
              : "Tanggal terdaftar tidak tersedia",
          style: const TextStyle(fontSize: 12, color: _textMuted),
        ),

        const SizedBox(height: 28),

        // Tombol Kembali
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _backToDashboard,
            style: ElevatedButton.styleFrom(
              backgroundColor: _btnColor,
              foregroundColor: _btnText,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text("Kembali", style: TextStyle(fontSize: 15)),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Registrasi Wajah",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          children: [
            // Step indicator
            _buildStepIndicator(),
            const SizedBox(height: 28),

            // Konten per step dengan animasi
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0.2, 0),
                  end: Offset.zero,
                ).animate(animation);
                return SlideTransition(
                  position: offsetAnimation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Container(
                key: ValueKey<int>(_currentStep),
                child: _buildStepContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _faceDetector.close();
    _faceService.dispose();
    super.dispose();
  }
}
