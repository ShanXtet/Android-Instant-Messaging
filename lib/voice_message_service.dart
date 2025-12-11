// lib/voice_message_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'file_service.dart';

class VoiceMessageService {
  static final VoiceMessageService _instance = VoiceMessageService._internal();
  factory VoiceMessageService() => _instance;
  VoiceMessageService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentRecordingPath;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  final ValueNotifier<int> durationNotifier = ValueNotifier<int>(0);

  bool get isRecording => _isRecording;
  int get recordingDuration => _recordingDuration;

  Future<bool> startRecording() async {
    try {
      // Check if already recording
      if (_isRecording) {
        debugPrint('Already recording');
        return false;
      }

      // Check and request permission
      if (!await _recorder.hasPermission()) {
        debugPrint('Microphone permission denied');
        return false;
      }

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/voice_$timestamp.m4a';

      // Start recording - start() returns void, not bool
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      // If we get here, recording started successfully
      _isRecording = true;
      _recordingDuration = 0;
      durationNotifier.value = 0;

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isRecording) {
          _recordingDuration++;
          durationNotifier.value = _recordingDuration;
        } else {
          timer.cancel();
        }
      });

      debugPrint('Recording started: $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _isRecording = false;
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) return null;

      final path = await _recorder.stop();
      _isRecording = false;
      _recordingTimer?.cancel();
      _recordingTimer = null;

      if (path != null && path.isNotEmpty) {
        _currentRecordingPath = path;
        return path;
      }
      return _currentRecordingPath;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      _recordingTimer?.cancel();
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        await _recorder.stop();
        _isRecording = false;
        _recordingTimer?.cancel();
        _recordingTimer = null;
      }

      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _currentRecordingPath = null;
      }
      _recordingDuration = 0;
      durationNotifier.value = 0;
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }

  String formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<String?> uploadAndGetUrl(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) return null;

    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    return await FileService().uploadFile(
      filePath: audioPath,
      fileName: fileName,
      mimeType: 'audio/m4a',
    );
  }

  Future<bool> hasMicrophonePermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('Error checking microphone permission: $e');
      return false;
    }
  }

  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
  }
}

