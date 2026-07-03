import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';

class AuthService {
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // ← TAMBAHAN: print full response
      debugPrint('🔍 FULL RESPONSE LOGIN: ${jsonEncode(data)}');

      if (response.statusCode == 200 && data['success'] == true) {
        final token = data['token']?.toString();
        final user = data['user'];

        // ← TAMBAHAN: print user object saja
        debugPrint('🔍 USER OBJECT: ${jsonEncode(user)}');

        if (token == null || token.isEmpty || user is! Map<String, dynamic>) {
          throw Exception('Response login tidak lengkap.');
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        await prefs.setString(AppConstants.userKey, jsonEncode(user));

        return data;
      }

      throw Exception(data['message'] ?? 'Login gagal.');
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Response server tidak valid.');
      }
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }
}