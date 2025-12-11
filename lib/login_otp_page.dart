import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'auth_store.dart';
import 'home_page.dart';

class LoginOTPPage extends StatefulWidget {
  final String phone;
  final String sessionId;

  const LoginOTPPage({
    super.key,
    required this.phone,
    required this.sessionId,
  });

  @override
  State<LoginOTPPage> createState() => _LoginOTPPageState();
}

class _LoginOTPPageState extends State<LoginOTPPage> {
  final _form = GlobalKey<FormState>();
  final otp = TextEditingController();
  bool loading = false;
  int countdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    otp.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (countdown > 0) {
            countdown--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _resendOTP() async {
    if (loading || countdown > 0) return;

    setState(() => loading = true);

    try {
      final res = await http.post(
        Uri.parse('$apiBase/api/auth/send-otp-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': widget.phone,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        },
      );

      final responseBody = res.body;
      debugPrint('Resend OTP response: ${res.statusCode} - $responseBody');

      if (res.statusCode == 200 || res.statusCode == 201) {
        _toast('OTP code sent successfully');
        _startCountdown();
      } else {
        _toast('Failed to resend OTP. Please try again.');
      }
    } catch (e) {
      debugPrint('Resend OTP error: $e');
      _toast('Failed to resend OTP. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _verifyOTP() async {
    if (otp.text.trim().length != 6) {
      _toast('Please enter a valid 6-digit OTP code');
      return;
    }
    if (loading) return;

    setState(() => loading = true);

    try {
      final res = await http.post(
        Uri.parse('$apiBase/api/auth/verify-otp-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'otp': otp.text.trim(),
          'sessionId': widget.sessionId,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        },
      );

      final responseBody = res.body;
      debugPrint('Verify OTP response: ${res.statusCode} - $responseBody');

      if (res.statusCode == 200) {
        try {
          final p = jsonDecode(responseBody) as Map<String, dynamic>;
          final token = p['token']?.toString();
          final userData = p['user'];
          
          if (token == null || token.isEmpty) {
            _toast('Login failed: No token received');
            setState(() => loading = false);
            return;
          }
          
          if (userData == null) {
            _toast('Login failed: No user data received');
            setState(() => loading = false);
            return;
          }
          
          final user = Map<String, dynamic>.from(userData);
          await AuthStore.save(token, user);

          if (!mounted) return;
          _toast('Welcome back!');
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
            (_) => false,
          );
        } catch (e) {
          debugPrint('Error parsing response: $e');
          _toast('Login failed: Invalid server response');
          setState(() => loading = false);
        }
      } else if (res.statusCode == 400) {
        try {
          final errorData = jsonDecode(responseBody) as Map<String, dynamic>;
          final error = errorData['error']?.toString() ?? 'invalid_otp';
          if (error == 'invalid_otp') {
            _toast('Invalid OTP code. Please try again.');
          } else if (error == 'expired_otp') {
            _toast('OTP code has expired. Please request a new one.');
            Navigator.pop(context);
          } else {
            _toast('Login failed: $error');
          }
        } catch (_) {
          _toast('Invalid OTP code. Please try again.');
        }
        setState(() => loading = false);
      } else {
        try {
          final errorData = jsonDecode(responseBody) as Map<String, dynamic>;
          final error = errorData['error']?.toString() ?? 'unknown_error';
          _toast('Login failed: $error (${res.statusCode})');
        } catch (_) {
          _toast('Login failed (${res.statusCode}). Please try again.');
        }
        setState(() => loading = false);
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout error: $e');
      _toast('Connection timeout. Please try again.');
      setState(() => loading = false);
    } on http.ClientException catch (e) {
      debugPrint('Network error: $e');
      _toast('Network error: Could not connect to server.');
      setState(() => loading = false);
    } on FormatException catch (e) {
      debugPrint('Format error: $e');
      _toast('Error: Invalid server response format');
      setState(() => loading = false);
    } catch (e) {
      debugPrint('Unexpected error: $e');
      _toast('An unexpected error occurred: ${e.toString()}');
      setState(() => loading = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF00BFFF);
    const deepBlue = Color(0xFF0099CC);
    const accentBlue = Color(0xFF66D9FF);

    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00BFFF), Color(0xFF0080B3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: -60,
                right: -30,
                child: Opacity(
                  opacity: 0.25,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -40,
                child: Opacity(
                  opacity: 0.18,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: accentBlue,
                      borderRadius: BorderRadius.circular(90),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Form(
                    key: _form,
                    child: Column(
                      children: [
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                              ),
                              child: const Icon(
                                Icons.lock_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Verification',
                                    style: textTheme.titleMedium?.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  Text(
                                    'Enter OTP Code',
                                    style: textTheme.headlineMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 30,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Verify OTP',
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: deepBlue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Enter the 6-digit code sent to\n${widget.phone}',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 28),
                              TextFormField(
                                controller: otp,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                maxLength: 6,
                                textInputAction: TextInputAction.done,
                                autofocus: true,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 8,
                                ),
                                decoration: InputDecoration(
                                  hintText: '000000',
                                  hintStyle: TextStyle(
                                    fontSize: 24,
                                    color: Colors.grey.shade300,
                                    letterSpacing: 8,
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline, color: primaryBlue),
                                  filled: true,
                                  fillColor: const Color(0xFFE6F7FF),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: const BorderSide(color: primaryBlue, width: 1.6),
                                  ),
                                  counterText: '',
                                ),
                                onChanged: (value) {
                                  if (value.length == 6) {
                                    // Auto-submit when 6 digits are entered
                                    _verifyOTP();
                                  }
                                },
                                onFieldSubmitted: (_) {
                                  // Also submit when user presses done on keyboard
                                  if (otp.text.length == 6) {
                                    _verifyOTP();
                                  }
                                },
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: loading ? null : _verifyOTP,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryBlue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(Colors.white),
                                          ),
                                        )
                                      : const Text(
                                          'Verify',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Didn't receive code?",
                                    style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: (countdown > 0 || loading) ? null : _resendOTP,
                                    style: TextButton.styleFrom(
                                      foregroundColor: primaryBlue,
                                    ),
                                    child: Text(
                                      countdown > 0 ? 'Resend in ${countdown}s' : 'Resend',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: countdown > 0 ? Colors.grey : primaryBlue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

