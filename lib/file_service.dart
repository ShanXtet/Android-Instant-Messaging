// lib/file_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'api.dart';
import 'auth_store.dart';

class FileService {
  static final FileService _instance = FileService._internal();
  factory FileService() => _instance;
  FileService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  /// Pick an image from gallery or camera
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      return image;
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// Pick a video from gallery or camera
  Future<XFile?> pickVideo({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );
      return video;
    } catch (e) {
      debugPrint('Error picking video: $e');
      return null;
    }
  }

  /// Pick a file from device
  Future<PlatformFile?> pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single;
      }
      return null;
    } catch (e) {
      debugPrint('Error picking file: $e');
      return null;
    }
  }

  /// Upload file to server and return file URL
  Future<String?> uploadFile({
    required String filePath,
    required String fileName,
    String? mimeType,
  }) async {
    try {
      final token = await AuthStore.getToken();
      if (token == null) return null;

      final file = File(filePath);
      if (!await file.exists()) return null;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBase/upload'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: fileName,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          // Server returns: {"url": "http://...", "fileName": "...", "fileSize": ...}
          final url = jsonData['url']?.toString();
          if (url != null && url.isNotEmpty) {
            return url;
          }
          // Fallback
          return '$apiBase/files/$fileName';
        } catch (e) {
          debugPrint('Error parsing upload response: $e');
          return '$apiBase/files/$fileName';
        }
      } else {
        debugPrint('Upload failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
      return null;
    }
  }

  /// Upload image from XFile
  Future<String?> uploadImage(XFile imageFile) async {
    return await uploadFile(
      filePath: imageFile.path,
      fileName: imageFile.name,
      mimeType: imageFile.mimeType,
    );
  }

  /// Upload file from PlatformFile
  Future<String?> uploadPlatformFile(PlatformFile platformFile) async {
    if (platformFile.path == null) return null;
    return await uploadFile(
      filePath: platformFile.path!,
      fileName: platformFile.name,
      mimeType: platformFile.extension,
    );
  }

  /// Get file size in human readable format
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Check if file is an image
  bool isImageFile(String? fileName) {
    if (fileName == null) return false;
    final ext = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  /// Get file icon based on extension
  IconData getFileIcon(String? fileName) {
    if (fileName == null) return Icons.insert_drive_file;
    final ext = fileName.toLowerCase().split('.').last;
    
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
        return Icons.audiotrack;
      case 'mp4':
      case 'avi':
        return Icons.video_file;
      default:
        return Icons.insert_drive_file;
    }
  }
}

