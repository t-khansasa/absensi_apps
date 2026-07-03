
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

class ApiClient {
  static Dio? _dio;

  static Future<Dio> getInstance() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey) ?? '';

    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ),
    );

    // Logging interceptor (debug only)
    _dio!.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
      ),
    );

    return _dio!;
  }

  // Helper: Parsing error message dari response Dio
  static String parseError(DioException e) {
    if (e.response != null && e.response!.data != null) {
      final data = e.response!.data;
      if (data is Map) {
        return data['message'] ?? data['error'] ?? 'Terjadi kesalahan';
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Koneksi timeout. Periksa jaringan kamu.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Tidak dapat terhubung ke server. Pastikan Laragon aktif.';
    }
    return e.message ?? 'Terjadi kesalahan';
  }
}


