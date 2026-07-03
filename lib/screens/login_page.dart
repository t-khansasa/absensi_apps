import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void handleLogin() async {
    if (_isLoading) return;

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Email dan password wajib diisi."),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.login(email, password);
      final Map<String, dynamic> userData = result['user'];
      final String token = result['token'];
      userData['token'] = token;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.blue,
          content: Text("Login Berhasil!"),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardPage(userData: userData),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(e.toString().replaceAll("Exception: ", "")),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A2246), Color(0xFF1D4461), Color(0xFF90CAF9)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ── Bagian atas dengan logo mengambang ──
                Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      height: screenSize.height * 0.35,
                      width: double.infinity,
                    ),

                    // Logo bulat — dinaikkan lebih tinggi dari card
                    Positioned(
                      bottom: 25, // ← key change: logo lebih naik
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Kontainer form bawah ──
                Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    minHeight: screenSize.height * 0.50,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9BB7D4).withOpacity(0.4),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(60),
                      topRight: Radius.circular(60),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 45,
                    vertical: 50,
                  ),
                  child: Column(
                    children: [
                      // Ruang untuk logo overlap — diperbesar
                      const SizedBox(height: 30), // ← key change
                      // INPUT EMAIL
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFC2D3E4),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(
                            color: const Color(0xFF1A3E5D).withOpacity(0.4),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0A1D33).withOpacity(0.5),
                              offset: const Offset(0, 12),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: emailController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Color(0xFF5C728A)),
                          decoration: const InputDecoration(
                            hintText: "Email",
                            hintStyle: TextStyle(
                              color: Color(0xFF7A94B2),
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 35),

                      // INPUT PASSWORD
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFC8DAEC),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(
                            color: const Color(0xFF1A3E5D).withOpacity(0.4),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0A1D33).withOpacity(0.5),
                              offset: const Offset(0, 12),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: passwordController,
                          obscureText:
                              _obscurePassword, // ← dari true menjadi variabel
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF5C728A)),
                          decoration: InputDecoration(
                            hintText: "Password",
                            hintStyle: const TextStyle(
                              color: Color(0xFF7A94B2),
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                            // ← tambahkan prefixIcon kosong sebagai penyeimbang
                            prefixIcon: const SizedBox(width: 48),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: const Color(0xFF7A94B2),
                              ),
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 70),

                      // TOMBOL MASUK
                      Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFF020E31),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.6),
                              offset: const Offset(0, 15),
                              blurRadius: 15,
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Masuk",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
