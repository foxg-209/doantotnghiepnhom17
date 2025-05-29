import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController fullNameController = TextEditingController();
  String? selectedGender;
  DateTime? selectedDate;
  bool isLoading = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> register() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String confirmPassword = confirmPasswordController.text.trim();
    String fullName = fullNameController.text.trim();

    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty || fullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Vui lòng nhập đầy đủ thông tin!")));
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Mật khẩu không khớp!")));
      return;
    }

    if (selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Vui lòng chọn giới tính!")));
      return;
    }

    if (selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Vui lòng chọn ngày sinh!")));
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'gender': selectedGender,
          'date_of_birth': selectedDate!.toIso8601String(),
        },
      );

      if (response.user != null) {
        if (response.user!.confirmedAt != null) {
          // Nếu tài khoản đã được xác thực (xác thực email bị tắt)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Đăng ký thành công! Bạn có thể đăng nhập ngay.")));
          Navigator.pop(context);
        } else {
          // Nếu tài khoản chưa được xác thực (xác thực email được bật)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Đăng ký thành công! Vui lòng kiểm tra email (kể cả thư mục Spam) để xác thực tài khoản.")));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      String errorMessage = "Lỗi đăng ký: ${e.toString()}";
      if (e.toString().contains("Email rate limit exceeded")) {
        errorMessage = "Đã vượt quá giới hạn gửi email. Vui lòng thử lại sau hoặc cấu hình SMTP tùy chỉnh.";
      } else if (e.toString().contains("Email address not authorized")) {
        errorMessage = "Email không được phép nhận thư. Vui lòng thêm email vào danh sách được phép trong Supabase.";
      } else if (e.toString().contains("SMTP")) {
        errorMessage = "Lỗi gửi email qua SMTP. Vui lòng kiểm tra lại cấu hình SMTP trong Supabase.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)));
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
                    "TẠO TÀI KHOẢN SMART HOME",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 30),
                  _buildTextField(fullNameController, "Họ và tên", Icons.person),
                  SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      hintText: "Chọn giới tính",
                      prefixIcon: Icon(Icons.wc, color: Colors.teal.shade700),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    ),
                    value: selectedGender,
                    items: ['Nam', 'Nữ', 'Khác']
                        .map((gender) => DropdownMenuItem(
                      value: gender,
                      child: Text(gender),
                    ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedGender = value;
                      });
                    },
                  ),
                  SizedBox(height: 15),
                  GestureDetector(
                    onTap: () => _selectDate(context),
                    child: AbsorbPointer(
                      child: _buildTextField(
                        TextEditingController(
                          text: selectedDate == null
                              ? ''
                              : '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                        ),
                        "Ngày tháng năm sinh",
                        Icons.calendar_today,
                      ),
                    ),
                  ),
                  SizedBox(height: 15),
                  _buildTextField(emailController, "Email", Icons.email),
                  SizedBox(height: 15),
                  _buildTextField(passwordController, "Mật khẩu", Icons.lock, isPassword: true),
                  SizedBox(height: 15),
                  _buildTextField(
                      confirmPasswordController, "Nhập lại mật khẩu", Icons.lock, isPassword: true),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: isLoading ? null : register,
                    child: isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Đăng ký', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  SizedBox(height: 15),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Đã có tài khoản? Đăng nhập ngay",
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