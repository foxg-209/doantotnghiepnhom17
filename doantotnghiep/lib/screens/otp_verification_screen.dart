// Xác nhận OTP
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String email;
  final bool isResetPassword;

  const OTPVerificationScreen({
    required this.email,
    required this.isResetPassword,
    super.key,
  });

  @override
  _OTPVerificationScreenState createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController otpController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  bool isLoading = false;

  Future<void> verifyOTPAndResetPassword() async {
    String otp = otpController.text.trim();
    String newPassword = newPasswordController.text.trim();

    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vui lòng nhập mã OTP!")),
      );
      return;
    }

    if (widget.isResetPassword && newPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vui lòng nhập mật khẩu mới!")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await supabase.auth.verifyOTP(
        type: widget.isResetPassword ? OtpType.recovery : OtpType.signup,
        email: widget.email,
        token: otp,
      );

      if (widget.isResetPassword && response.user != null) {
        await supabase.auth.updateUser(UserAttributes(password: newPassword));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Đặt lại mật khẩu thành công!")),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Xác nhận OTP thành công!")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi: ${e.toString()}")),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isResetPassword ? 'Đặt lại mật khẩu' : 'Xác nhận OTP'),
        backgroundColor: Colors.teal,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal.shade100, Colors.teal.shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Nhập mã OTP gửi tới ${widget.email}",
                style: TextStyle(fontSize: 18, color: Colors.teal.shade900),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 30),
              _buildTextField(otpController, "Nhập mã OTP", Icons.lock),
              if (widget.isResetPassword) ...[
                SizedBox(height: 20),
                _buildTextField(newPasswordController, "Mật khẩu mới", Icons.lock, isPassword: true),
              ],
              SizedBox(height: 30),
              ElevatedButton(
                onPressed: isLoading ? null : verifyOTPAndResetPassword,
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  widget.isResetPassword ? "Đặt lại mật khẩu" : "Xác nhận",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
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
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}