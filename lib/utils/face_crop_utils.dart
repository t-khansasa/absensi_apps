import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Utility untuk mendeteksi wajah dari sebuah file foto (hasil takePicture),
/// lalu meng-crop area wajah tersebut dengan margin, dan menyimpannya
/// sebagai file baru. Dipakai bersama di FaceRegistrationScreen & ScanScreen
/// supaya proses crop SAMA PERSIS antara saat registrasi dan saat absen.
class FaceCropUtils {
  /// Margin tambahan di sekitar bounding box wajah (dalam persen dari
  /// lebar/tinggi bounding box). Margin diperlukan supaya tidak terlalu
  /// ketat memotong dagu/dahi, karena MobileFaceNet biasanya dilatih
  /// dengan crop yang menyertakan sedikit area di luar wajah inti.
  static const double _marginRatio = 0.35;

  /// Mendeteksi & crop wajah dari [imageFile] (hasil CameraController.takePicture()).
  ///
  /// Mengembalikan File baru (JPEG) berisi area wajah yang sudah di-crop,
  /// atau null jika tidak ada wajah terdeteksi pada gambar statis tersebut.
  static Future<File?> detectAndCropFace({
    required File imageFile,
    required FaceDetector faceDetector,
  }) async {
    // 1. Jalankan deteksi wajah pada gambar STATIS (bukan stream CameraImage).
    //    InputImage.fromFilePath otomatis menangani orientasi EXIF foto JPEG,
    //    jadi tidak perlu rotation/format manual seperti saat proses stream.
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final faces = await faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      return null;
    }

    // 2. Ambil wajah dengan bounding box terbesar (paling dekat ke kamera),
    //    untuk jaga-jaga kalau ML Kit mendeteksi lebih dari satu wajah.
    Face mainFace = faces.first;
    double maxArea = 0;
    for (final face in faces) {
      final area = face.boundingBox.width * face.boundingBox.height;
      if (area > maxArea) {
        maxArea = area;
        mainFace = face;
      }
    }

    // 3. Decode gambar asli dengan package `image`.
    final bytes = await imageFile.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // 4. Pastikan orientasi EXIF foto sudah benar sebelum dihitung crop-nya.
    decoded = img.bakeOrientation(decoded);

    final box = mainFace.boundingBox;

    // 5. Tambahkan margin di sekeliling bounding box.
    final marginX = box.width * _marginRatio;
    final marginY = box.height * _marginRatio;

    int left = (box.left - marginX).round();
    int top = (box.top - marginY).round();
    int right = (box.right + marginX).round();
    int bottom = (box.bottom + marginY).round();

    // 6. Clamp supaya tidak keluar batas gambar.
    left = left.clamp(0, decoded.width - 1);
    top = top.clamp(0, decoded.height - 1);
    right = right.clamp(left + 1, decoded.width);
    bottom = bottom.clamp(top + 1, decoded.height);

    final cropWidth = right - left;
    final cropHeight = bottom - top;

    if (cropWidth <= 0 || cropHeight <= 0) return null;

    // 7. Crop gambar sesuai area wajah + margin.
    final cropped = img.copyCrop(
      decoded,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );

    // 8. Simpan hasil crop sebagai file sementara baru.
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/face_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 95));

    return outFile;
  }
}