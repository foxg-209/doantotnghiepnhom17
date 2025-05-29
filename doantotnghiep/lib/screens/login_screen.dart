// Đăng nhập tài khoản
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;

  Future<bool> checkInternet() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> login() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Vui lòng nhập email và mật khẩu!")));
      return;
    }

    if (!await checkInternet()) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Không có kết nối internet!")));
      return;
    }

    setState(() => isLoading = true);

    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Đăng nhập thất bại! Hãy kiểm tra email/mật khẩu.")));
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal.shade100, Colors.teal.shade50],
          ),
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.home, size: 100, color: Colors.teal.shade700),
                  SizedBox(height: 20),
                  Text(
                    "CHÀO MỪNG ĐẾN SMART HOME",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 30),
                  _buildTextField(emailController, "Email", Icons.email),
                  SizedBox(height: 15),
                  _buildTextField(passwordController, "Mật khẩu", Icons.lock, isPassword: true),
                  SizedBox(height: 15),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                      child: Text("Quên mật khẩu?", style: TextStyle(color: Colors.teal.shade700)),
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: isLoading ? null : login,
                    child: isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Đăng nhập', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  SizedBox(height: 15),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                    child: Text("Chưa có tài khoản? Đăng ký ngay",
                        style: TextStyle(color: Colors.teal.shade700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.teal.shade700),
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}