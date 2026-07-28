import 'dart:io';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class FaceRecognitionService {
  Interpreter? _interpreter;

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
      print("Model Face Recognition Berhasil Dimuat!");
    } catch (e) {
      print("Gagal memuat model: $e");
      rethrow;
    }
  }

  List<double> predict(File faceImage) {
    if (_interpreter == null) {
      throw Exception("Model belum dimuat. Coba lagi nanti.");
    }

    try {
      img.Image? image = img.decodeImage(faceImage.readAsBytesSync());
      if (image == null) {
        throw Exception("Gagal mendekode gambar. Pastikan gambar valid.");
      }

      // Tidak perlu flip manual lagi di sini, karena file yang masuk
      // sudah berupa hasil crop dari FaceCropUtils yang sudah
      // di-bakeOrientation dengan benar.
      img.Image resizedImage = img.copyResize(image, width: 112, height: 112);
      var input = _imageToInput(resizedImage);
      var output = List.generate(1, (_) => List.filled(192, 0.0));

      _interpreter!.run(input, output);

      return List<double>.from(output[0]);
    } catch (e) {
      throw Exception("Error dalam pemrosesan wajah: $e");
    }
  }

  List<List<List<List<double>>>> _imageToInput(img.Image image) {
    return List.generate(
      1,
      (_) => List.generate(
        112,
        (i) => List.generate(112, (j) {
          final pixel = image.getPixel(j, i);
          return [
            (pixel.r - 128) / 128,
            (pixel.g - 128) / 128,
            (pixel.b - 128) / 128,
          ];
        }),
      ),
    );
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  // ── FIX 2: turunkan threshold dari 0.6 → 0.45 ──
  bool isSameFace(
    List<double> embedding1,
    List<double> embedding2, {
    double threshold = 0.45,
  }) {
    final similarity = cosineSimilarity(embedding1, embedding2);
    print('Cosine similarity: $similarity');
    print('Threshold: $threshold');
    print('Hasil: ${similarity >= threshold ? "COCOK ✓" : "TIDAK COCOK ✗"}');
    return similarity >= threshold;
  }

  // ── BARU: khusus untuk keperluan logging pengujian skripsi ──
  // Mengembalikan angka similarity mentah (bukan cuma true/false),
  // supaya bisa dicatat ke log CSV untuk dianalisis di BAB IV.
  double getSimilarityScore(List<double> embedding1, List<double> embedding2) {
    return cosineSimilarity(embedding1, embedding2);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}