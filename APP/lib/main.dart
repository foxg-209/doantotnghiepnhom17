import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';         // Import màn hình đăng nhập
import 'screens/register_screen.dart';      // Import màn hình đăng ký
import 'screens/forgot_password_screen.dart'; // Import màn hình quên mật khẩu
import 'screens/otp_verification_screen.dart'; // Import màn hình xác nhận OTP
import 'screens/home_screen.dart';          // Import màn hình chính

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    //url: 'https://rdlmnlpbwvnofwxgbwaf.supabase.co', // Thay bằng URL của bạn
    //anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJkbG1ubHBid3Zub2Z3eGdid2FmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDI4Mjk1ODAsImV4cCI6MjA1ODQwNTU4MH0.6sc2OJJ5j3yzeHMcRRgMd__Di9QnB-tpxaUd_Zczd3Q', // Thay bằng Anon Key của bạn
      url: 'https://fglrhaqjcsohzyqgmqei.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZnbHJoYXFqY3NvaHp5cWdtcWVpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQxMTAxNTQsImV4cCI6MjA1OTY4NjE1NH0.NGS3fGa1qho-8JzmFNHNIhEIDnv-fu6Tk_HTvomt1es',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home Control',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.teal.shade50,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/forgot-password': (context) => ForgotPasswordScreen(),
        '/otp-verification': (context) => OTPVerificationScreen(email: '', isResetPassword: true),
        '/home': (context) => HomeScreen(),
      },
    );
  }
}