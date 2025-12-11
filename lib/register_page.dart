import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api.dart'; // apiBase
import 'auth_store.dart'; // save()
import 'home_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final otp = TextEditingController();
  bool loading = false;
  bool otpSent = false;
  String? sessionId;
  int countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    password.dispose();
    confirmPassword.dispose();
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

  Future<void> _sendOTP() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (loading) return;
    
    // Validate phone number format
    final phoneNumber = phone.text.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (phoneNumber.isEmpty || phoneNumber.length < 10) {
      _toast('Please enter a valid phone number');
      return;
    }

    setState(() => loading = true);

    try {
      final res = await http.post(
        Uri.parse('$apiBase/api/auth/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phoneNumber,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        },
      );

      final responseBody = res.body;
      debugPrint('Send OTP response: ${res.statusCode} - $responseBody');

      if (res.statusCode == 200 || res.statusCode == 201) {
        try {
          final p = jsonDecode(responseBody) as Map<String, dynamic>;
          sessionId = p['sessionId']?.toString();
          final otpCode = p['otp']?.toString(); // OTP returned in development mode
          
          if (sessionId == null || sessionId!.isEmpty) {
            _toast('Failed to send OTP: No session ID received');
            return;
          }
          
          setState(() {
            otpSent = true;
            loading = false;
          });
          _startCountdown();
          
          // Show OTP in dialog for testing (development mode)
          if (otpCode != null && otpCode.isNotEmpty) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('OTP Code (Testing)'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('For testing purposes, your OTP code is:'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          otpCode,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Phone: ${phone.text.trim()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            }
          } else {
            _toast('OTP sent to your phone number');
          }
        } catch (e) {
          debugPrint('Error parsing response: $e');
          _toast('Failed to send OTP: Invalid server response');
          setState(() => loading = false);
        }
      } else if (res.statusCode == 409) {
        _toast('Phone number already registered. Please use a different number.');
        setState(() => loading = false);
      } else if (res.statusCode == 400) {
        _toast('Invalid phone number format');
        setState(() => loading = false);
      } else {
        try {
          final errorData = jsonDecode(responseBody) as Map<String, dynamic>;
          final error = errorData['error']?.toString() ?? 'unknown_error';
          _toast('Failed to send OTP: $error');
        } catch (_) {
          _toast('Failed to send OTP (${res.statusCode}). Please try again.');
        }
        setState(() => loading = false);
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout error: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Connection Timeout'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cannot connect to the server.'),
                const SizedBox(height: 8),
                Text('Server: $apiBase'),
                const SizedBox(height: 16),
                const Text('Possible solutions:'),
                const SizedBox(height: 8),
                const Text('1. Check if backend server is running'),
                const Text('2. Verify IP address is correct'),
                const Text('3. Ensure phone and computer are on same WiFi'),
                const Text('4. Check firewall settings'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      setState(() => loading = false);
    } on http.ClientException catch (e) {
      debugPrint('Network error: $e');
      _toast('Network error: Could not connect to server. Please check your internet connection and ensure the server is running at $apiBase');
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

  Future<void> _verifyOTPAndRegister() async {
    if (otp.text.trim().length != 6) {
      _toast('Please enter a valid 6-digit OTP code');
      return;
    }
    if (password.text.trim().length < 6) {
      _toast('Password must be at least 6 characters');
      return;
    }
    if (password.text.trim() != confirmPassword.text.trim()) {
      _toast('Passwords do not match');
      return;
    }
    if (loading) return;
    if (sessionId == null || sessionId!.isEmpty) {
      _toast('Please request OTP first');
      return;
    }

    setState(() => loading = true);

    try {
      final phoneNumber = phone.text.trim().replaceAll(RegExp(r'[^\d+]'), '');
      final res = await http.post(
        Uri.parse('$apiBase/api/auth/verify-otp-register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name.text.trim(),
          'phone': phoneNumber,
          'otp': otp.text.trim(),
          'sessionId': sessionId,
          'password': password.text.trim(),
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        },
      );

      final responseBody = res.body;
      debugPrint('Verify OTP response: ${res.statusCode} - $responseBody');

      if (res.statusCode == 201 || res.statusCode == 200) {
        try {
          final p = jsonDecode(responseBody) as Map<String, dynamic>;
          final token = p['token']?.toString();
          final userData = p['user'];
          
          if (token == null || token.isEmpty) {
            _toast('Registration failed: No token received');
            return;
          }
          
          if (userData == null) {
            _toast('Registration failed: No user data received');
            return;
          }
          
          final user = Map<String, dynamic>.from(userData);
          await AuthStore.save(token, user);

          if (!mounted) return;
          _toast('Account created successfully!');
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
            (_) => false,
          );
        } catch (e) {
          debugPrint('Error parsing response: $e');
          _toast('Registration failed: Invalid server response');
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
            setState(() {
              otpSent = false;
              sessionId = null;
            });
          } else {
            _toast('Registration failed: $error');
          }
        } catch (_) {
          _toast('Invalid OTP code. Please try again.');
        }
        setState(() => loading = false);
      } else if (res.statusCode == 409) {
        _toast('Phone number already registered. Please use a different number.');
        setState(() => loading = false);
      } else {
        try {
          final errorData = jsonDecode(responseBody) as Map<String, dynamic>;
          final error = errorData['error']?.toString() ?? 'unknown_error';
          _toast('Registration failed: $error (${res.statusCode})');
        } catch (_) {
          _toast('Registration failed (${res.statusCode}). Please try again.');
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
    const primaryPurple = Color(0xFF7F4AC7);
    const deepPurple = Color(0xFF5B2BAF);
    const accentPink = Color(0xFFEC6FFF);

    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF8C5CFB), Color(0xFF45106E)],
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
                      color: accentPink,
                      borderRadius: BorderRadius.circular(90),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
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
                              Icons.person_add_rounded,
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
                                  'Create account',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: Colors.white.withOpacity(0.8),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                Text(
                                  'Join the community',
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
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                otpSent ? 'Verify OTP' : 'Sign up',
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: deepPurple,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                otpSent
                                    ? 'Enter the 6-digit code sent to your phone'
                                    : 'Enter your details to get started.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 28),
                              if (!otpSent) ...[
                                _ViberField(
                                  label: 'Full Name',
                                  controller: name,
                                  icon: Icons.person_rounded,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                                ),
                                const SizedBox(height: 16),
                                _ViberField(
                                  label: 'Phone Number',
                                  controller: phone,
                                  icon: Icons.phone_rounded,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'[\d+\-() ]')),
                                  ],
                                  validator: (v) => (v == null || v.trim().length < 10)
                                      ? 'Enter a valid phone number (min 10 digits)'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                _ViberField(
                                  label: 'Password',
                                  controller: password,
                                  icon: Icons.lock_rounded,
                                  obscureText: true,
                                  textInputAction: TextInputAction.next,
                                  validator: (v) => (v == null || v.trim().length < 6)
                                      ? 'Password must be at least 6 characters'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                _ViberField(
                                  label: 'Confirm Password',
                                  controller: confirmPassword,
                                  icon: Icons.lock_outline_rounded,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Please confirm your password';
                                    }
                                    if (v.trim() != password.text.trim()) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: loading ? null : _sendOTP,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryPurple,
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
                                            'Send OTP',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ] else ...[
                                _ViberField(
                                  label: 'OTP Code',
                                  controller: otp,
                                  icon: Icons.lock_clock_rounded,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  maxLength: 6,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  onFieldSubmitted: (_) => _verifyOTPAndRegister(),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "Didn't receive code?",
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    TextButton(
                                      onPressed: countdown > 0
                                          ? null
                                          : () {
                                              setState(() {
                                                otpSent = false;
                                                sessionId = null;
                                                otp.clear();
                                              });
                                            },
                                      style: TextButton.styleFrom(
                                        foregroundColor: primaryPurple,
                                      ),
                                      child: Text(
                                        countdown > 0 ? 'Resend in ${countdown}s' : 'Resend OTP',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: loading ? null : _verifyOTPAndRegister,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryPurple,
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
                                            'Verify & Create Account',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Already have an account?",
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: TextButton.styleFrom(
                                      foregroundColor: deepPurple,
                                    ),
                                    child: const Text('Sign in'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
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

class _ViberField extends StatelessWidget {
  const _ViberField({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onToggleObscure,
    this.maxLength,
    this.inputFormatters,
    this.onFieldSubmitted,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final void Function(String)? onFieldSubmitted;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF7F4AC7)),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscureText ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF7F4AC7),
                ),
              ),
        filled: true,
        fillColor: const Color(0xFFF7F2FF),
        enabledBorder: border,
        border: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: Color(0xFF7F4AC7), width: 1.6),
        ),
        counterText: '',
      ),
    );
  }
}
