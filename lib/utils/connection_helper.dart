import '../api.dart';
import 'package:flutter/material.dart';

/// Connection Helper Utility
/// Helps diagnose and fix connection issues
class ConnectionHelper {
  /// Test connection and show results in a dialog
  static Future<void> testAndShowDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Testing connection...'),
              ],
            ),
          ),
        ),
      ),
    );

    final result = await testConnection();

    if (!context.mounted) return;

    Navigator.pop(context); // Close loading dialog

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result['success'] == true ? '✅ Connection Successful' : '❌ Connection Failed'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('API Base: ${result['apiBase']}'),
              const SizedBox(height: 8),
              if (result['success'] == true) ...[
                Text('Status: ${result['statusCode']}'),
                Text('Message: ${result['message']}'),
              ] else ...[
                Text('Error: ${result['error']}'),
                const SizedBox(height: 16),
                const Text(
                  'Troubleshooting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('1. Make sure backend server is running'),
                const Text('2. Check if IP address is correct'),
                const Text('3. Verify firewall is not blocking'),
                const Text('4. For emulator, use 10.0.2.2'),
                const Text('5. For real device, use your PC\'s LAN IP'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (result['success'] != true)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                testAndShowDialog(context);
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  /// Get connection status message
  static String getConnectionStatusMessage(Map<String, dynamic> result) {
    if (result['success'] == true) {
      return 'Connected to ${result['apiBase']}';
    } else {
      return 'Cannot connect to ${result['apiBase']}\nError: ${result['error']}';
    }
  }
}

