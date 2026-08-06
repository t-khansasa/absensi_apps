import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/face_recognition_service.dart';
import '../services/verification_log_service.dart';
import '../services/scenario_picker_dialog.dart';
import '../utils/constants.dart';
import '../utils/face_crop_utils.dart';
import 'success_screen.dart';
import 'dart:convert';
import 'dart:io';

/// Hasil verifikasi wajah, dipisah supaya pesan error ke user lebih akurat
/// (membedakan "belum registrasi" vs "wajah tidak cocok" vs "gagal diproses").
enum FaceVerifyResult { match, notRegistered, mismatch, skipped }

/// Tahapan liveness detection: kedip mata -> geleng kiri -> geleng kanan -> selesai
enum LivenessStep { blink, turnLeft, turnRight, completed }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  final FaceRecognitionService _faceService = FaceRecognitionService();
  bool _isFaceModelLoaded = false;

  // ── untuk keperluan logging pengujian skripsi ──
  final VerificationLogService _logService = VerificationLogService();
  TestScenario? _selectedScenario;
  final Stopwatch _verificationStopwatch = Stopwatch();
  double _lastSimilarityScore = 0.0;

  bool _isBusy = false;
  bool _faceDetected = false;
  bool _isSubmitting = false;
  bool _autoSubmitTriggered = false;

  // ── PERUBAHAN 1: Naikkan threshold ke 35 frame (~7 detik @ ~5fps) ────────
  int _stableFaceFrames = 0;
  static const int _stableFrameThreshold = 15;

  // ── Liveness detection: blink + head movement ──
  bool _livenessVerified = false;
  LivenessStep _currentLivenessStep = LivenessStep.blink;

  int _blinkCount = 0;
  bool _eyesWereClosed = false;
  static const int _blinkThreshold = 1; // minimal 1x kedip

  // Threshold sudut kepala dalam derajat (headEulerAngleY = yaw, kiri-kanan)
  static const double _headTurnThreshold = 15.0;
  bool _headTurnLeftDone = false;
  bool _headTurnRightDone = false;

  bool _isCheckingLocation = true;
  bool _isInsideRadius = false;
  String _locationStatusMessage = "Mengecek lokasi...";

  double? _officeLatitude;
  double? _officeLongitude;
  double _allowedRadiusMeters = 100.0;
  bool _isTestingMode = false;

  Position? _currentPosition;

  // ── Geolocator real-time ──
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _loadFaceModel();
    _fetchOfficeAndCheck();
  }

  Future<void> _loadFaceModel() async {
    try {
      await _faceService.loadModel();
      _isFaceModelLoaded = true;
      debugPrint('Face model loaded untuk verifikasi');
    } catch (e) {
      debugPrint('Gagal load face model: $e');
    }
  }

  Future<void> _fetchOfficeAndCheck() async {
    if (!mounted) return;
    setState(() {
      _isCheckingLocation = true;
      _locationStatusMessage = "Mengambil data kantor...";
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);

      if (token != null) {
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
            final lat = double.tryParse(office['latitude']?.toString() ?? '');
            final lng = double.tryParse(office['longitude']?.toString() ?? '');
            final radius = double.tryParse(office['radius']?.toString() ?? '');
            final testingMode = office['is_testing_mode'];

            if (lat != null && lng != null) {
              _officeLatitude = lat;
              _officeLongitude = lng;
              _allowedRadiusMeters = radius ?? 100.0;
              _isTestingMode = testingMode == true || testingMode == 1 || testingMode == '1';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Gagal fetch office: $e');
    }

    await _checkLocationAndInit();
  }

  Future<void> _checkLocationAndInit() async {
    if (!mounted) return;
    setState(() {
      _isCheckingLocation = true;
      _locationStatusMessage = "Mengecek lokasi GPS...";
    });

    final position = await _determinePosition();

    if (position == null) {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _isInsideRadius = false;
        _locationStatusMessage =
            "Gagal mendapatkan lokasi. Pastikan GPS aktif.";
      });
      // ── Auto-kembali ke beranda kalau GPS gagal didapat ──────────────
      _showError(_locationStatusMessage);
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    if (!mounted) return;
    setState(() => _currentPosition = position);

    if (_officeLatitude == null || _officeLongitude == null) {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _isInsideRadius = true;
        _locationStatusMessage =
            "Lokasi kantor tidak tersedia, absensi diizinkan.";
      });
      await _initCamera();
      _startPositionStream();
      return;
    }

    // ── Mode Testing: skip pengecekan radius DAN kamera/wajah di sisi HP
    // sepenuhnya. Kamera nggak pernah dinyalain, jadi liveness & face
    // verification nggak jadi penghalang. Cukup kirim koordinat + akurasi
    // GPS langsung ke backend, yang akan menghitung effective_radius &
    // mencatat hasilnya (diterima/ditolak) ke tabel tolerance_coefficient_tests.
    // Ini penting supaya tester nggak perlu jadi user terdaftar dengan wajah
    // ter-enroll — siapapun bisa dipakai sebagai partisipan uji titik. ──
    if (_isTestingMode) {
      if (!mounted) return;
      setState(() {
        _isCheckingLocation = false;
        _isInsideRadius = true;
        _locationStatusMessage =
            "Mode Testing aktif \u2014 mengirim lokasi langsung ke backend.";
      });
      await _submitTestingAttendance(position);
      return;
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _officeLatitude!,
      _officeLongitude!,
    );

    final inside = distance <= _allowedRadiusMeters;

    if (!mounted) return;

    setState(() {
      _isCheckingLocation = false;
      _isInsideRadius = inside;
      _locationStatusMessage = inside
          ? "Lokasi terverifikasi (${distance.toStringAsFixed(0)}m dari kantor)"
          : "Kamu berada ${distance.toStringAsFixed(0)}m dari kantor. Absensi hanya bisa dilakukan dalam radius ${_allowedRadiusMeters.toStringAsFixed(0)}m.";
    });

    if (inside) {
      await _initCamera();
      _startPositionStream(); // ── mulai tracking lokasi real-time ──
    } else {
      // ── Auto-kembali ke beranda kalau di luar radius kantor ──────────
      _showError(_locationStatusMessage);
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  /// Mulai memantau posisi user secara real-time selama proses scan
  /// berlangsung. Kalau user keluar radius kantor di tengah proses,
  /// absensi otomatis dibatalkan.
  void _startPositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // update tiap user bergerak 5 meter
    );

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {
          if (!mounted) return;

          setState(() => _currentPosition = position);

          if (!_isTestingMode && _officeLatitude != null && _officeLongitude != null) {
            final distance = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              _officeLatitude!,
              _officeLongitude!,
            );

            final stillInside = distance <= _allowedRadiusMeters;

            if (!stillInside && _isInsideRadius) {
              // User baru saja keluar radius saat proses berlangsung
              setState(() {
                _isInsideRadius = false;
                _locationStatusMessage =
                    "Kamu keluar dari radius kantor (${distance.toStringAsFixed(0)}m). Absensi dibatalkan.";
              });
              _showError(_locationStatusMessage);
              _positionStream?.cancel();
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) Navigator.pop(context);
              });
            }
          }
        });
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras[0],
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      _controller!.startImageStream((CameraImage image) {
        if (_isBusy) return;
        _isBusy = true;
        _detectFace(image);
      });

      if (!mounted) return;
      setState(() => _isCameraInitialized = true);

      // ── munculkan dialog pilih skenario pengujian ──
      // (khusus masa pengumpulan data skripsi; bisa dihapus/disembunyikan
      // nanti setelah masa pengujian selesai)
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _selectedScenario = await showScenarioPickerDialog(context);
      });
    } catch (e) {
      debugPrint("Gagal inisialisasi kamera: $e");
    }
  }

  Future<void> _detectFace(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final InputImageMetadata metadata = InputImageMetadata(
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

      if (hasFace && faces.isNotEmpty) {
        final face = faces.first;
        _processLivenessStep(face);
      }

      if (mounted) {
        setState(() {
          _faceDetected = hasFace;
          _stableFaceFrames = hasFace ? _stableFaceFrames + 1 : 0;
          if (!hasFace) {
            _resetLiveness();
          }
        });
      }
      // ── Hanya submit jika liveness verified ──
      if (hasFace &&
          _stableFaceFrames >= _stableFrameThreshold &&
          _livenessVerified &&
          !_isSubmitting &&
          !_autoSubmitTriggered) {
        _autoSubmitTriggered = true;
        Future.microtask(_captureAndSubmit);
      }
    } catch (e) {
      debugPrint("Error deteksi wajah: $e");
    }
    _isBusy = false;
  }

  /// State machine liveness: blink -> turnLeft -> turnRight -> completed.
  /// headEulerAngleY = yaw (geleng kiri/kanan).
  ///
  /// CATATAN PERBAIKAN MIRROR: kamera depan pada device ini menghasilkan
  /// nilai yaw terbalik dari asumsi awal (geleng kiri fisik menghasilkan
  /// yaw positif, bukan negatif) — tanda perbandingan di kedua step di
  /// bawah sudah ditukar untuk menyesuaikan.
  void _processLivenessStep(Face face) {
    switch (_currentLivenessStep) {
      case LivenessStep.blink:
        final leftEye = face.leftEyeOpenProbability ?? 1.0;
        final rightEye = face.rightEyeOpenProbability ?? 1.0;
        final eyesClosed = leftEye < 0.3 && rightEye < 0.3;

        if (eyesClosed && !_eyesWereClosed) {
          _eyesWereClosed = true;
        } else if (!eyesClosed && _eyesWereClosed) {
          _eyesWereClosed = false;
          _blinkCount++;
          debugPrint('👁️ Kedipan terdeteksi: $_blinkCount');
          if (_blinkCount >= _blinkThreshold) {
            debugPrint('✅ Step blink selesai → lanjut turnLeft');
            _currentLivenessStep = LivenessStep.turnLeft;
          }
        }
        break;

      case LivenessStep.turnLeft:
        final yaw = face.headEulerAngleY ?? 0.0;
        // Tanda ditukar (>= bukan <=) untuk mengoreksi mirror kamera depan.
        if (yaw >= _headTurnThreshold) {
          _headTurnLeftDone = true;
          debugPrint('↩️ Geleng kiri terdeteksi (yaw: $yaw)');
          _currentLivenessStep = LivenessStep.turnRight;
        }
        break;

      case LivenessStep.turnRight:
        final yaw = face.headEulerAngleY ?? 0.0;
        // Tanda ditukar (<= bukan >=) untuk mengoreksi mirror kamera depan.
        if (yaw <= -_headTurnThreshold) {
          _headTurnRightDone = true;
          debugPrint('↪️ Geleng kanan terdeteksi (yaw: $yaw)');
          _currentLivenessStep = LivenessStep.completed;
          _livenessVerified = true;
          debugPrint('✅ Liveness verified (blink + head movement)');
        }
        break;

      case LivenessStep.completed:
        break;
    }
  }

  void _resetLiveness() {
    _currentLivenessStep = LivenessStep.blink;
    _eyesWereClosed = false;
    _blinkCount = 0;
    _headTurnLeftDone = false;
    _headTurnRightDone = false;
    _livenessVerified = false;
  }

  Future<Position?> _determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('GPS belum aktif. Nyalakan lokasi dulu ya.');
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showError('Izin lokasi ditolak. Absensi butuh lokasi GPS.');
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Verifikasi wajah hasil crop terhadap embedding tersimpan di server.
  /// Mengembalikan [FaceVerifyResult] supaya pemanggil bisa menampilkan
  /// pesan yang akurat (belum registrasi vs tidak cocok vs match vs gagal proses).
  Future<FaceVerifyResult> _verifyFace(File capturedImage) async {
    if (!_isFaceModelLoaded) {
      debugPrint('Model belum load, skip verifikasi');
      return FaceVerifyResult.skipped;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      if (token == null) return FaceVerifyResult.skipped;

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/face-embedding'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 404) {
        debugPrint('Wajah belum terdaftar, absensi DITOLAK');
        return FaceVerifyResult.notRegistered;
      }
      if (response.statusCode != 200) {
        debugPrint('Gagal ambil embedding: ${response.statusCode}');
        return FaceVerifyResult.skipped;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true || data['embedding'] == null) {
        return FaceVerifyResult.skipped;
      }

      final storedEmbedding = List<double>.from(
        (data['embedding'] as List).map((e) => double.parse(e.toString())),
      );

      final currentEmbedding = _faceService.predict(capturedImage);
      final isSame = _faceService.isSameFace(storedEmbedding, currentEmbedding);

      // ── simpan angka similarity mentah untuk logging ──
      _lastSimilarityScore =
          _faceService.getSimilarityScore(storedEmbedding, currentEmbedding);

      debugPrint(
        'Hasil verifikasi wajah: ${isSame ? "COCOK ✓" : "TIDAK COCOK ✗"}',
      );
      return isSame ? FaceVerifyResult.match : FaceVerifyResult.mismatch;
    } catch (e) {
      debugPrint('Error verifikasi wajah: $e');
      return FaceVerifyResult.skipped;
    }
  }

  /// Ambil tenantId & userId dari data user yang tersimpan di SharedPreferences
  /// (disimpan saat login oleh AuthService sebagai JSON di bawah AppConstants.userKey).
  ///
  /// Catatan: field 'company' di data user berupa STRING nama perusahaan
  /// (misal "PT. Surya Gaya Dharmaputra"), BUKAN ID numerik — sudah dikonfirmasi
  /// dari hasil debugPrint('USER OBJECT: ...') saat login.
  Future<Map<String, String>> _getUserContext() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(AppConstants.userKey);

    if (userJson == null || userJson.isEmpty) {
      return {'tenantId': 'unknown_tenant', 'userId': 'unknown_user'};
    }

    try {
      final user = jsonDecode(userJson) as Map<String, dynamic>;

      final userId = user['id']?.toString() ?? 'unknown_user';

      final tenantId = user['company']?.toString() ??
          user['tenant']?.toString() ??
          'unknown_tenant';

      return {'tenantId': tenantId, 'userId': userId};
    } catch (e) {
      debugPrint('Gagal parse user context untuk logging: $e');
      return {'tenantId': 'unknown_tenant', 'userId': 'unknown_user'};
    }
  }

  /// Simpan hasil percobaan ke log CSV lokal, khusus kalau sedang mode
  /// pengujian (skenario sudah dipilih lewat dialog).
  Future<void> _logTestResult(FaceVerifyResult result) async {
    final context = await _getUserContext();
    final tenantId = context['tenantId']!;
    final userId = context['userId']!;

    final attemptNumber = await _logService.getNextAttemptNumber(
      tenantId: tenantId,
      userId: userId,
      scenario: _selectedScenario!.label,
    );

    await _logService.logVerification(
      FaceVerificationLog(
        tenantId: tenantId,
        userId: userId,
        scenario: _selectedScenario!.label,
        attemptNumber: attemptNumber,
        similarityScore: _lastSimilarityScore,
        thresholdUsed: 0.45,
        livenessPassed: _livenessVerified,
        processingTimeMs: _verificationStopwatch.elapsedMilliseconds,
        deviceModel:
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        timestamp: DateTime.now(),
      ),
    );

    debugPrint(
      '📝 Log tersimpan: tenant=$tenantId, user=$userId, scenario=${_selectedScenario!.label}, attempt=$attemptNumber, score=$_lastSimilarityScore',
    );
  }

  // ── Mengirimkan accuracy, accuracy_in, dan accuracy_out ──
  Future<bool> _sendAttendance(XFile image, Position position) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey);

    if (token == null || token.isEmpty) {
      _showError('Token tidak ditemukan. Silakan login ulang.');
      return false;
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConstants.baseUrl}/attendance'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';

    request.fields['latitude'] = position.latitude.toString();
    request.fields['longitude'] = position.longitude.toString();

    // Mengirimkan nilai akurasi GPS ke semua kunci parameter yang mungkin digunakan backend
    request.fields['accuracy'] = position.accuracy.toString();
    request.fields['accuracy_in'] = position.accuracy.toString();
    request.fields['accuracy_out'] = position.accuracy.toString();

    request.fields['face_verified'] = _faceDetected ? '1' : '0';
    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    final streamedResponse = await request.send();
    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode == 200 ||
        streamedResponse.statusCode == 201) {
      return true;
    }

    String message = 'Gagal mengirim absensi.';
    try {
      final data = responseBody.isNotEmpty
          ? Map<String, dynamic>.from(
              await compute(_decodeJsonMap, responseBody),
            )
          : <String, dynamic>{};
      message = data['message']?.toString() ?? message;
    } catch (_) {
      if (responseBody.isNotEmpty) message = responseBody;
    }

    _showError(message);
    return false;
  }

  static Map<String, dynamic> _decodeJsonMap(String source) {
    return Map<String, dynamic>.from(jsonDecode(source) as Map);
  }

  /// Khusus mode testing (is_testing_mode aktif di kantor): kirim koordinat
  /// + akurasi GPS langsung ke backend TANPA kamera, TANPA liveness, TANPA
  /// verifikasi wajah. Backend sudah didesain menerima request testing_mode
  /// tanpa field 'image' sama sekali, jadi partisipan siapapun (nggak harus
  /// user dengan wajah ter-enroll) bisa dipakai buat uji titik geofencing.
  Future<void> _submitTestingAttendance(Position position) async {
    if (!mounted) return;
    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);

      if (token == null || token.isEmpty) {
        _showError('Token tidak ditemukan. Silakan login ulang.');
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.baseUrl}/attendance'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      request.fields['latitude'] = position.latitude.toString();
      request.fields['longitude'] = position.longitude.toString();
      request.fields['accuracy'] = position.accuracy.toString();
      // Sengaja tidak melampirkan 'image' — testing_mode di backend
      // sudah nullable untuk field ini.

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      String message = 'Testing selesai.';
      try {
        final data = responseBody.isNotEmpty
            ? Map<String, dynamic>.from(
                await compute(_decodeJsonMap, responseBody),
              )
            : <String, dynamic>{};
        message = data['message']?.toString() ?? message;
      } catch (_) {
        if (responseBody.isNotEmpty) message = responseBody;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.blue, content: Text(message)),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showError('Gagal mengirim data testing: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _captureAndSubmit() async {
    if (_controller == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
      await Future.delayed(const Duration(milliseconds: 500));

      if (_controller == null || !_controller!.value.isInitialized) return;

      final image = await _controller!.takePicture();

      // ── Crop wajah dari foto sebelum dipakai untuk verifikasi ──
      final croppedFace = await FaceCropUtils.detectAndCropFace(
        imageFile: File(image.path),
        faceDetector: _faceDetector,
      );

      if (croppedFace == null) {
        _showError('Wajah tidak terdeteksi dengan jelas. Coba lagi.');
        _autoSubmitTriggered = false;
        _stableFaceFrames = 0;
        await _restartImageStream();
        return;
      }

      final position = await _determinePosition();

      if (position == null) {
        await _restartImageStream();
        return;
      }

      if (mounted) setState(() => _currentPosition = position);

      if (!_isTestingMode && _officeLatitude != null && _officeLongitude != null) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _officeLatitude!,
          _officeLongitude!,
        );

        if (distance > _allowedRadiusMeters) {
          _showError(
            'Kamu sudah keluar dari radius kantor (${distance.toStringAsFixed(0)}m). Absensi dibatalkan.',
          );
          _autoSubmitTriggered = false;
          _stableFaceFrames = 0;
          await _restartImageStream();
          return;
        }
      }

      // ── Verifikasi wajah: bedakan "belum registrasi" vs "tidak cocok" vs "gagal proses" ──
      _verificationStopwatch.reset();
      _verificationStopwatch.start();
      final verifyResult = await _verifyFace(croppedFace);
      _verificationStopwatch.stop();

      // ── simpan hasil ke log kalau sedang mode testing ──
      if (_selectedScenario != null) {
        await _logTestResult(verifyResult);
      }

      // ── PERBAIKAN KEAMANAN: 'skipped' sekarang ikut diblokir ──
      // Sebelumnya hanya notRegistered & mismatch yang diblokir, sehingga
      // kegagalan proses verifikasi (koneksi timeout, response API gagal,
      // dll) membuat absensi tetap lolos tanpa wajah benar-benar tercocokkan.
      if (verifyResult == FaceVerifyResult.notRegistered ||
          verifyResult == FaceVerifyResult.mismatch ||
          verifyResult == FaceVerifyResult.skipped) {
        if (!mounted) return;

        final message = switch (verifyResult) {
          FaceVerifyResult.notRegistered =>
            'Wajah belum terdaftar! Silakan registrasi wajah terlebih dahulu.',
          FaceVerifyResult.mismatch =>
            'Wajah tidak dikenali! Pastikan wajah kamu sesuai dengan yang terdaftar.',
          _ =>
            'Verifikasi wajah gagal diproses. Periksa koneksi internet dan coba lagi.',
        };

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );

        // Tunggu snackbar selesai lalu auto kembali ke beranda
        await Future.delayed(const Duration(seconds: 4));
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }

      // ── MODE TESTING: kalau skenario dipilih, cukup verifikasi + logging,
      // TIDAK submit absensi sungguhan — supaya tidak kena batas 2x/hari
      // (absen masuk & pulang) dan tidak mengotori data presensi asli tenant.
      if (_selectedScenario != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.blue,
            content: Text(
              'Mode testing: verifikasi selesai, absensi tidak disubmit.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }

      final success = await _sendAttendance(image, position);
      if (!mounted) return;

      if (success) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SuccessScreen()),
        ).then((res) {
          if (res == true && mounted) Navigator.pop(context, true);
        });
      } else {
        // ── Gagal submit (misal: sudah absen masuk hari ini) → auto kembali ──
        if (!mounted) return;
        await Future.delayed(const Duration(seconds: 4));
        if (!mounted) return;
        Navigator.pop(context);
      }
    } catch (e) {
      _showError('Gagal mengambil/mengirim foto: $e');
      _autoSubmitTriggered = false;
      _stableFaceFrames = 0;
      await _restartImageStream();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _restartImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_controller!.value.isStreamingImages) {
      await _controller!.startImageStream((CameraImage image) {
        if (_isBusy) return;
        _isBusy = true;
        _detectFace(image);
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red, content: Text(message)),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final double aspectRatio = controller.value.aspectRatio;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 1,
          height: aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _controller?.dispose();
    _faceDetector.close();
    _faceService.dispose();
    super.dispose();
  }

  // ─── Loading Screen ───────────────────────────────────────────────────────
  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF7777BB)),
            const SizedBox(height: 24),
            Text(
              _locationStatusMessage,
              style: const TextStyle(color: Color(0xFF888899), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Out of Radius Screen ─────────────────────────────────────────────────
  Widget _buildOutOfRadiusScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_off_outlined,
                color: Color(0xFF994444),
                size: 72,
              ),
              const SizedBox(height: 24),
              const Text(
                "Di luar area absensi",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _locationStatusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF888899),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(color: Color(0xFF7777BB)),
              const SizedBox(height: 16),
              const Text(
                "Mengembalikan ke beranda...",
                style: TextStyle(color: Color(0xFF666677), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Main Scan Screen ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isCheckingLocation) return _buildLoadingScreen();
    if (!_isInsideRadius) return _buildOutOfRadiusScreen();

    const double ovalWidth = 220.0;
    const double ovalHeight = 270.0;

    final Color ovalBorderColor = _faceDetected
        ? const Color(0xFF44BB88)
        : const Color(0xFF3A3A5C);

    final String statusText = _isSubmitting
        ? "Memproses Absensi . . ."
        : _faceDetected
        ? switch (_currentLivenessStep) {
            LivenessStep.blink => "Kedipkan mata untuk verifikasi...",
            LivenessStep.turnLeft => "Sekarang, geleng kepala ke kiri...",
            LivenessStep.turnRight => "Bagus! Sekarang geleng ke kanan...",
            LivenessStep.completed => "Verifikasi berhasil, memproses...",
          }
        : "Arahkan wajah ke bingkai";

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: Stack(
        children: [
          // ── Layer 1: Kamera live (full screen) ──────────────────────────
          if (_isCameraInitialized) _buildCameraPreview(),

          // ── Layer 2: Overlay gelap menutupi seluruh layar ───────────────
          Container(color: Colors.black.withOpacity(0.60)),

          // ── Layer 3: Konten utama ────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Color(0xFF888899),
                      size: 28,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFF888899),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _currentPosition != null
                          ? '${_currentPosition!.latitude.toStringAsFixed(10)}, '
                                '${_currentPosition!.longitude.toStringAsFixed(8)}'
                          : 'Memuat koordinat...',
                      style: const TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                Expanded(
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(ovalWidth),
                          child: SizedBox(
                            width: ovalWidth,
                            height: ovalHeight,
                            child: _isCameraInitialized
                                ? _buildCameraPreview()
                                : Container(color: const Color(0xFF1C1C2C)),
                          ),
                        ),
                        Container(
                          width: ovalWidth,
                          height: ovalHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(ovalWidth),
                            border: Border.all(
                              color: ovalBorderColor,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Text(
                        statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF999AAA),
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),

                      if (_faceDetected && !_isSubmitting) ...[
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 60),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (_stableFaceFrames / _stableFrameThreshold)
                                  .clamp(0.0, 1.0),
                              backgroundColor: const Color(0xFF2A2A3E),
                              color: const Color(0xFF44BB88),
                              minHeight: 4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14143A),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'Absen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF7777BB),
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Layer 4: Full-screen loading saat submit ─────────────────────
          if (_isSubmitting)
            Container(
              color: Colors.black.withOpacity(0.70),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF7777BB)),
                    SizedBox(height: 16),
                    Text(
                      "Memproses absensi...",
                      style: TextStyle(color: Color(0xFF999AAA), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}