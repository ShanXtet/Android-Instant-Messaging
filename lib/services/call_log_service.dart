import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_log.dart';
import '../auth_store.dart';
import '../api.dart';
import 'package:http/http.dart' as http;

/// Call Log Service
/// Manages call history storage and retrieval
class CallLogService {
  static const String _keyPrefix = 'call_logs_';
  
  /// Get all call logs for current user
  static Future<List<CallLog>> getCallLogs() async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return [];
      
      final userId = user['id']?.toString() ?? '';
      if (userId.isEmpty) return [];
      
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      final jsonStr = prefs.getString(key);
      
      if (jsonStr == null || jsonStr.isEmpty) return [];
      
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((json) => CallLog.fromJson(json as Map<String, dynamic>)).toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime)); // Newest first
    } catch (e) {
      debugPrint('Error loading call logs: $e');
      return [];
    }
  }
  
  /// Save a call log
  static Future<void> saveCallLog(CallLog callLog) async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return;
      
      final userId = user['id']?.toString() ?? '';
      if (userId.isEmpty) return;
      
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      
      // Get existing logs
      final existing = await getCallLogs();
      
      // Check for duplicates by:
      // 1. Same ID
      // 2. Same peer + start time (within 5 seconds) - regardless of type
      // This prevents duplicate logs from both participants (outgoing/incoming for same call)
      CallLog? duplicateLog;
      bool shouldReplace = false;
      
      for (final log in existing) {
        if (log.id == callLog.id) {
          duplicateLog = log;
          break;
        }
        
        // Check if same call by peer and time (within 5 seconds)
        // This catches cases where caller logs "outgoing" and callee logs "incoming" for the same call
        final timeDiff = (log.startTime.difference(callLog.startTime).abs().inSeconds);
        if (log.peerId == callLog.peerId && timeDiff <= 5) {
          duplicateLog = log;
          // Prefer keeping the one with more complete information (has duration)
          if (callLog.duration != null && log.duration == null) {
            shouldReplace = true;
          }
          break;
        }
      }
      
      if (duplicateLog != null) {
        if (shouldReplace) {
          // Replace the existing log with the new one (which has duration)
          final updated = existing.where((log) => log.id != duplicateLog!.id).toList();
          updated.add(callLog);
          updated.sort((a, b) => b.startTime.compareTo(a.startTime));
          final limited = updated.take(1000).toList();
          final jsonList = limited.map((log) => log.toJson()).toList();
          await prefs.setString(key, jsonEncode(jsonList));
          debugPrint('Replaced call log with more complete version: ${callLog.id}');
        } else {
          debugPrint('Duplicate call log detected, skipping: ${callLog.id}');
        }
        return;
      }
      
      // Add new log
      final updated = List<CallLog>.from(existing);
      updated.add(callLog);
      
      // Sort by time (newest first)
      updated.sort((a, b) => b.startTime.compareTo(a.startTime));
      
      // Limit to last 1000 calls to prevent storage bloat
      final limited = updated.take(1000).toList();
      
      // Save back
      final jsonList = limited.map((log) => log.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving call log: $e');
    }
  }
  
  // Track sent call activity messages to prevent duplicates
  static final Set<String> _sentCallActivityIds = <String>{};
  static final Set<String> _loggedCallIds = <String>{}; // Track logged calls
  
  /// Create and save a call log from call details
  static Future<void> logCall({
    required String callId,
    required String peerId,
    String? peerName,
    String? peerEmail,
    String? peerAvatarUrl,
    required CallType type,
    required CallStatus status,
    required DateTime startTime,
    DateTime? endTime,
    Duration? duration,
    bool isVideoCall = false,
  }) async {
    // Check if we already logged this call
    if (_loggedCallIds.contains(callId)) {
      debugPrint('Call already logged: $callId');
      return;
    }
    _loggedCallIds.add(callId);
    
    // Check if we already sent a message for this call
    if (_sentCallActivityIds.contains(callId)) {
      debugPrint('Call activity message already sent for call: $callId');
      // Still save the log even if message was already sent
      final callLog = CallLog(
        id: callId,
        peerId: peerId,
        peerName: peerName,
        peerEmail: peerEmail,
        peerAvatarUrl: peerAvatarUrl,
        type: type,
        status: status,
        startTime: startTime,
        endTime: endTime,
        duration: duration,
        isVideoCall: isVideoCall,
      );
      await saveCallLog(callLog);
      return;
    }
    
    final callLog = CallLog(
      id: callId,
      peerId: peerId,
      peerName: peerName,
      peerEmail: peerEmail,
      peerAvatarUrl: peerAvatarUrl,
      type: type,
      status: status,
      startTime: startTime,
      endTime: endTime,
      duration: duration,
      isVideoCall: isVideoCall,
    );
    
    await saveCallLog(callLog);
    
    // Send call activity message for:
    // 1. All outgoing calls (from caller's side)
    // 2. Incoming missed/rejected calls (from receiver's side) - like Viber
    // This ensures both participants see call history in chat
    bool shouldSendMessage = false;
    
    if (type == CallType.outgoing && !_sentCallActivityIds.contains(callId)) {
      // Outgoing calls: always send from caller's side
      shouldSendMessage = true;
      debugPrint('Sending call activity message for outgoing call: $callId');
    } else if (type == CallType.incoming && !_sentCallActivityIds.contains(callId)) {
      // Incoming calls: only send missed calls. Skip declined so caller's single
      // "declined" message is the only one (prevents duplicates).
      if (status == CallStatus.missed) {
        shouldSendMessage = true;
        debugPrint('Sending call activity message for incoming missed call: $callId');
      } else {
        debugPrint('Skipping incoming call activity (declined/completed) to avoid duplicates: $callId');
      }
    } else {
      debugPrint('Call activity message already sent, skipping: $callId');
    }
    
    if (shouldSendMessage) {
      _sentCallActivityIds.add(callId);
      await _sendCallActivityMessage(callLog);
      
      // Clean up old IDs after 1 hour to prevent memory bloat
      Future.delayed(const Duration(hours: 1), () {
        _sentCallActivityIds.remove(callId);
        _loggedCallIds.remove(callId);
      });
    }
  }
  
  /// Send call activity message to chat
  /// IMPORTANT: Only send from the caller (outgoing) side to prevent duplicates
  /// Both participants will see the same single message
  static Future<void> _sendCallActivityMessage(CallLog callLog) async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return;
      
      final myId = user['id']?.toString() ?? '';
      if (myId.isEmpty) return;
      
      // Determine message text based on call status and type
      // The widget will generate proper text, this is just fallback
      String messageText;
      
      if (callLog.type == CallType.outgoing) {
        // Outgoing calls
      switch (callLog.status) {
        case CallStatus.completed:
          if (callLog.duration != null && callLog.duration!.inSeconds > 0) {
            messageText = '📞 Outgoing call (${callLog.formatDuration()})';
          } else {
            messageText = '📞 Outgoing call';
          }
          break;
        case CallStatus.missed:
          messageText = '📞 Missed call';
          break;
        case CallStatus.rejected:
          messageText = '📞 Declined call';
          break;
        case CallStatus.cancelled:
          messageText = '📞 Outgoing call';
          break;
      }
      } else {
        // Incoming calls (missed or rejected)
        switch (callLog.status) {
          case CallStatus.missed:
            messageText = '📞 Missed call';
            break;
          case CallStatus.rejected:
            messageText = '📞 Declined call';
            break;
          default:
            messageText = '📞 Incoming call';
            break;
        }
      }
      
      // Get peer's phone number - try to fetch from API if we only have ID
      String? peerPhone = callLog.peerEmail; // peerEmail might actually be phone
      
      // If peerEmail is not a phone number, try to get phone from user ID
      if (peerPhone == null || !peerPhone.startsWith('+')) {
        try {
          // Try to get user info by ID
          final response = await http.get(
            Uri.parse('$apiBase/users/by-ids?ids=${callLog.peerId}'),
            headers: await authHeaders(),
          );
          if (response.statusCode == 200) {
            final map = Map<String, dynamic>.from(jsonDecode(response.body));
            final peerData = map[callLog.peerId];
            if (peerData != null) {
              peerPhone = peerData['phone']?.toString() ?? 
                         peerData['email']?.toString() ?? 
                         callLog.peerId;
            }
          }
        } catch (e) {
          debugPrint('Error fetching peer phone: $e');
        }
      }
      
      // Fallback to peerId if phone not found
      peerPhone ??= callLog.peerId;
      
      // Send message via API only (don't use socket as fallback to avoid duplicates)
      // IMPORTANT: Include all metadata so widget can generate correct text
      final messageData = {
        'from': myId,
        'toPhone': peerPhone,
        'text': messageText, // This is just for fallback, widget generates its own text
        'messageType': 'call_activity',
        'callActivity': true,
        'callType': callLog.type.toString().split('.').last, // 'outgoing' or 'incoming'
        'callStatus': callLog.status.toString().split('.').last, // 'completed', 'missed', 'rejected', 'cancelled'
        'isVideoCall': callLog.isVideoCall,
        'callStartTime': callLog.startTime.toIso8601String(),
        'callDuration': callLog.duration?.inSeconds.toString(),
      };
      
      debugPrint('Sending call activity message: From=$myId, ToPhone=$peerPhone, Type=${callLog.type}, Status=${callLog.status}');
      
      try {
        final response = await http.post(
          Uri.parse('$apiBase/api/messages'),
          headers: await authHeaders(),
          body: jsonEncode(messageData),
        );
        
        if (response.statusCode != 200) {
          debugPrint('Failed to send call activity message: ${response.statusCode}');
        } else {
          debugPrint('Call activity message sent: ${callLog.type} call, status: ${callLog.status}');
        }
      } catch (e) {
        debugPrint('Error sending call activity message: $e');
        // Don't fallback to socket to avoid duplicates
      }
    } catch (e) {
      debugPrint('Error in _sendCallActivityMessage: $e');
    }
  }
  
  /// Delete a call log
  static Future<void> deleteCallLog(String callLogId) async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return;
      
      final userId = user['id']?.toString() ?? '';
      if (userId.isEmpty) return;
      
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      
      final existing = await getCallLogs();
      final updated = existing.where((log) => log.id != callLogId).toList();
      
      final jsonList = updated.map((log) => log.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error deleting call log: $e');
    }
  }
  
  /// Clear all call logs
  static Future<void> clearAllCallLogs() async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return;
      
      final userId = user['id']?.toString() ?? '';
      if (userId.isEmpty) return;
      
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      await prefs.remove(key);
    } catch (e) {
      debugPrint('Error clearing call logs: $e');
    }
  }
}

