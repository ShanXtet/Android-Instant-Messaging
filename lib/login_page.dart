// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import 'api.dart' hide apiBase;
// import 'auth_store.dart';
// import 'chats_page.dart';
// import 'register_page.dart'; // remove if unused

// class LoginPage extends StatefulWidget {
//   const LoginPage({super.key});
//   @override
//   State<LoginPage> createState() => _LoginPageState();
// }

// class _LoginPageState extends State<LoginPage> {
//   final email = TextEditingController();
//   final pass = TextEditingController();
//   bool loading = false;
//   bool obscure = true;

//   Future<void> _login() async {
//     if (loading) return;
//     setState(() => loading = true);

//     try {
//       final res = await http.post(
//         Uri.parse('$apiBase/auth/login'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'email': email.text.trim(), 'password': pass.text}),
//       );

//       if (res.statusCode == 200) {
//         final p = jsonDecode(res.body);
//         await AuthStore.save(p['token'], Map<String, dynamic>.from(p['user']));
//         if (!mounted) return;
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (_) => const ChatsPage()),
//         );
//       } else if (res.statusCode == 401) {
//         _toast('Invalid email or password');
//       } else {
//         _toast('Login failed (${res.statusCode})');
//       }
//     } catch (e) {
//       _toast('Network error: $e');
//     } finally {
//       if (mounted) setState(() => loading = false);
//     }
//   }

//   void _toast(String m) =>
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Login')),
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             children: [
//               TextField(
//                 controller: email,
//                 keyboardType: TextInputType.emailAddress,
//                 decoration: const InputDecoration(labelText: 'Email'),
//               ),
//               const SizedBox(height: 12),
//               TextField(
//                 controller: pass,
//                 obscureText: obscure,
//                 decoration: InputDecoration(
//                   labelText: 'Password',
//                   suffixIcon: IconButton(
//                     onPressed: () => setState(() => obscure = !obscure),
//                     icon: Icon(
//                       obscure ? Icons.visibility : Icons.visibility_off,
//                     ),
//                   ),
//                 ),
//                 onSubmitted: (_) => _login(),
//               ),
//               const SizedBox(height: 20),
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton.icon(
//                   onPressed: loading ? null : _login,
//                   icon: loading
//                       ? const SizedBox(
//                           width: 18,
//                           height: 18,
//                           child: CircularProgressIndicator(strokeWidth: 2),
//                         )
//                       : const Icon(Icons.login),
//                   label: const Text('Sign in'),
//                 ),
//               ),
//               const SizedBox(height: 8),
//               TextButton(
//                 onPressed: () {
//                   Navigator.push(
//                     context,
//                     MaterialPageRoute(builder: (_) => const RegisterPage()),
//                   );
//                 },
//                 child: const Text('Create an account'),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl_phone_field/intl_phone_field.dart';

import 'api.dart'; // apiBase, testConnection
import 'auth_store.dart'; // save(), clear()
import 'home_page.dart';
import 'login_otp_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _completePhoneNumber = '';
  bool loading = false;

  Future<void> _sendOTP() async {
    if (loading) return;
    
    // Basic validation
    if (_completePhoneNumber.trim().isEmpty) {
      _toast('Please enter your phone number');
      return;
    }
    
    // Validate phone number format (should include country code)
    if (_completePhoneNumber.length < 10) {
      _toast('Please enter a valid phone number');
      return;
    }
    
    setState(() => loading = true);

    try {
      final res = await http.post(
        Uri.parse('$apiBase/api/auth/send-otp-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': _completePhoneNumber,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout. Please check your internet connection.');
        },
      );

      final responseBody = res.body;
      debugPrint('Send OTP response: ${res.statusCode} - $responseBody');
      debugPrint('Request URL: $apiBase/api/auth/send-otp-login');

      if (res.statusCode == 200 || res.statusCode == 201) {
        try {
          final p = jsonDecode(responseBody) as Map<String, dynamic>;
          final sessionId = p['sessionId']?.toString();
          
          if (sessionId == null || sessionId.isEmpty) {
            _toast('Failed to send OTP: No session ID received');
            setState(() => loading = false);
            return;
          }

        if (!mounted) return;
          // Navigate to OTP verification page
          Navigator.push(
          context,
            MaterialPageRoute(
              builder: (_) => LoginOTPPage(
                phone: _completePhoneNumber,
                sessionId: sessionId,
              ),
            ),
        );
        } catch (e) {
          debugPrint('Error parsing response: $e');
          _toast('Failed to send OTP: Invalid server response');
        }
      } else if (res.statusCode == 400) {
        try {
          final errorData = jsonDecode(responseBody) as Map<String, dynamic>;
          final error = errorData['error']?.toString() ?? 'missing';
          if (error == 'invalid_phone') {
            _toast('Please enter a valid phone number');
          } else {
            _toast('Failed to send OTP: $error');
          }
        } catch (_) {
          _toast('Failed to send OTP. Please try again.');
        }
      } else if (res.statusCode == 409) {
        _toast('Phone number already registered. Please use a different number.');
      } else if (res.statusCode == 404) {
        debugPrint('❌ 404 Error - Endpoint not found');
        debugPrint('Request URL: $apiBase/api/auth/send-otp-login');
        debugPrint('Response body: $responseBody');
        _toast('Server endpoint not found. Please check if backend server is running and restarted.');
      } else {
        try {
          final errorData = jsonDecode(responseBody) as Map<String, dynamic>;
          final error = errorData['error']?.toString() ?? 'unknown_error';
          _toast('Failed to send OTP: $error (${res.statusCode})');
        } catch (_) {
          debugPrint('❌ Error response (${res.statusCode}): $responseBody');
          _toast('Failed to send OTP (${res.statusCode}). Please try again.');
        }
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
    } on http.ClientException catch (e) {
      debugPrint('Network error: $e');
      _toast('Network error: Could not connect to server. Please check your internet connection and ensure the server is running at $apiBase');
    } on FormatException catch (e) {
      debugPrint('Format error: $e');
      _toast('Error: Invalid server response format');
    } catch (e) {
      debugPrint('Unexpected error: $e');
      _toast('An unexpected error occurred: ${e.toString()}');
    } finally {
      if (mounted) setState(() => loading = false);
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
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 60),
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
                                  Icons.chat_bubble_rounded,
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
                                      'Welcome back',
                                      style: textTheme.titleMedium?.copyWith(
                                        color: Colors.white.withOpacity(0.8),
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    Text(
                                      'Instant Messaging',
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
                          SizedBox(height: constraints.maxHeight * 0.08),
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
                                  'Sign in',
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: deepBlue,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Connect with your favorite people.',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                IntlPhoneField(
                                  decoration: InputDecoration(
                                    labelText: 'Phone number',
                                    labelStyle: TextStyle(color: Colors.black.withOpacity(0.6)),
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
                                      borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.6),
                                    ),
                                  ),
                                  initialCountryCode: 'US',
                                  onChanged: (phone) {
                                    setState(() {
                                      _completePhoneNumber = phone.completeNumber;
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: loading ? null : _sendOTP,
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
                                            'Send OTP',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: constraints.maxHeight * 0.08),
                        ],
                      ),
                    ),
                  );
                },
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
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final VoidCallback? onToggleObscure;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.black.withOpacity(0.6)),
        prefixIcon: Icon(icon, color: const Color(0xFF00BFFF)),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscureText ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF00BFFF),
                ),
              ),
        filled: true,
        fillColor: const Color(0xFFE6F7FF),
        enabledBorder: border,
        border: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.6),
        ),
      ),
    );
  }
}
