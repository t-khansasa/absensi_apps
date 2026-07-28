import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Utility untuk mendeteksi wajah dari sebuah file foto (hasil takePicture),
/// meng-align wajah tersebut (meratakan posisi mata secara horizontal),
/// lalu meng-crop area wajah dengan margin, dan menyimpannya sebagai file
/// baru. Dipakai bersama di FaceRegistrationScreen & ScanScreen supaya
/// proses crop SAMA PERSIS antara saat registrasi dan saat absen.
///
/// PENTING: FaceDetector yang di-pass ke sini HARUS dibuat dengan
/// `enableLandmarks: true`, karena alignment butuh posisi mata kiri &
/// kanan. Tanpa ini, alignment akan di-skip otomatis (fallback ke
/// crop biasa tanpa rotasi).
class FaceCropUtils {
  /// Margin tambahan di sekitar bounding box wajah (dalam persen dari
  /// lebar/tinggi bounding box). Margin diperlukan supaya tidak terlalu
  /// ketat memotong dagu/dahi, karena MobileFaceNet biasanya dilatih
  /// dengan crop yang menyertakan sedikit area di luar wajah inti.
  static const double _marginRatio = 0.35;

  /// Ambang minimal kemiringan (derajat) sebelum rotasi alignment
  /// dilakukan. Kalau wajah sudah cukup rata, rotasi di-skip supaya
  /// tidak menambah proses/kualitas gambar yang tidak perlu.
  static const double _minAngleThresholdDeg = 1.0;

  /// Mendeteksi & crop wajah dari [imageFile] (hasil CameraController.takePicture()).
  ///
  /// Mengembalikan File baru (JPEG) berisi area wajah yang sudah
  /// di-align & di-crop, atau null jika tidak ada wajah terdeteksi.
  static Future<File?> detectAndCropFace({
    required File imageFile,
    required FaceDetector faceDetector,
  }) async {
    // 1. Deteksi wajah pertama kali pada gambar asli untuk dapat landmark mata.
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final faces = await faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      return null;
    }

    Face mainFace = _pickLargestFace(faces);

    // 2. Decode & perbaiki orientasi EXIF gambar asli.
    final bytes = await imageFile.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);

    // 3. Coba lakukan face alignment berdasarkan posisi mata.
    img.Image workingImage = decoded;
    Face faceForCrop = mainFace;

    final leftEye = mainFace.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = mainFace.landmarks[FaceLandmarkType.rightEye]?.position;

    if (leftEye != null && rightEye != null) {
      final dx = (rightEye.x - leftEye.x).toDouble();
      final dy = (rightEye.y - leftEye.y).toDouble();
      final angleDeg = atan2(dy, dx) * 180 / pi;

      if (angleDeg.abs() > _minAngleThresholdDeg) {
        // Rotasi gambar supaya garis antar-mata jadi horizontal.
        // img.copyRotate merotasi terhadap titik tengah gambar.
        final rotated = img.copyRotate(decoded, angle: angleDeg);

        // 4. Deteksi ulang wajah PADA gambar yang sudah dirotasi, karena
        //    bounding box lama sudah tidak valid setelah rotasi.
        final tempDir = await getTemporaryDirectory();
        final rotatedPath =
            '${tempDir.path}/face_rotated_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final rotatedFile = File(rotatedPath);
        await rotatedFile.writeAsBytes(img.encodeJpg(rotated, quality: 95));

        final rotatedInputImage = InputImage.fromFilePath(rotatedFile.path);
        final rotatedFaces = await faceDetector.processImage(
          rotatedInputImage,
        );

        // Hapus file sementara hasil rotasi, sudah tidak dibutuhkan lagi.
        unawaited(rotatedFile.delete().catchError((_) => rotatedFile));

        if (rotatedFaces.isNotEmpty) {
          workingImage = rotated;
          faceForCrop = _pickLargestFace(rotatedFaces);
        }
        // Kalau deteksi ulang gagal (jarang terjadi), fallback diam-diam
        // ke workingImage/faceForCrop semula (tanpa alignment).
      }
    }

    // 5. Hitung area crop dari bounding box (sudah wajah hasil align kalau ada).
    final box = faceForCrop.boundingBox;
    final marginX = box.width * _marginRatio;
    final marginY = box.height * _marginRatio;

    int left = (box.left - marginX).round();
    int top = (box.top - marginY).round();
    int right = (box.right + marginX).round();
    int bottom = (box.bottom + marginY).round();

    left = left.clamp(0, workingImage.width - 1);
    top = top.clamp(0, workingImage.height - 1);
    right = right.clamp(left + 1, workingImage.width);
    bottom = bottom.clamp(top + 1, workingImage.height);

    final cropWidth = right - left;
    final cropHeight = bottom - top;

    if (cropWidth <= 0 || cropHeight <= 0) return null;

    // 6. Crop gambar sesuai area wajah + margin.
    final cropped = img.copyCrop(
      workingImage,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );

    // 7. Simpan hasil crop sebagai file sementara baru.
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/face_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 95));

    return outFile;
  }

  /// Ambil wajah dengan bounding box terbesar (paling dekat ke kamera),
  /// untuk jaga-jaga kalau ML Kit mendeteksi lebih dari satu wajah.
  static Face _pickLargestFace(List<Face> faces) {
    Face mainFace = faces.first;
    double maxArea = 0;
    for (final face in faces) {
      final area = face.boundingBox.width * face.boundingBox.height;
      if (area > maxArea) {
        maxArea = area;
        mainFace = face;
      }
    }
    return mainFace;
  }
}

/// Helper kecil supaya Future hasil delete file tidak perlu di-await
/// tapi tetap ditangani (menghindari "unhandled future" warning).
void unawaited(Future<void> future) {}