// lib/utils/flexible_message_builder.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../file_service.dart';
import '../voice_message_player.dart';
import '../utils/responsive.dart';

class FlexibleMessageBuilder {
  static Widget buildMessage({
    required BuildContext context,
    required Map<String, dynamic> message,
    required bool isMe,
    required bool isDeleted,
    required String createdAt,
    required bool edited,
    required Function(String) onLongPress,
    required Widget Function(Map<String, dynamic>) tickWidget,
    required String Function(Map<String, dynamic>) statusText,
    required Color Function(String) statusColor,
  }) {
    final fileUrl = message['fileUrl']?.toString();
    final fileName = message['fileName']?.toString();
    final fileType = message['fileType']?.toString();
    final hasFile = fileUrl != null && fileUrl.isNotEmpty;
    final isImage = hasFile && (fileType == 'image' || FileService().isImageFile(fileName));
    final isVoice = hasFile && (fileType == 'audio' || fileType == 'voice' || 
        (fileName?.endsWith('.m4a') ?? false) || (fileName?.endsWith('.mp3') ?? false));
    final text = message['text']?.toString() ?? '';
    
    final maxWidth = Responsive.getMessageMaxWidth(context);
    
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          gradient: isDeleted
              ? null
              : LinearGradient(
                  colors: isMe
                      ? [
                          const Color(0xFF3A7BD5),
                          const Color(0xFF00D2FF),
                        ]
                      : [
                          const Color(0xFF00C853),
                          const Color(0xFFB2FF59),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isDeleted ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // File/Image/Voice display
            if (hasFile && !isDeleted) ...[
              const SizedBox(height: 4),
              if (isVoice)
                VoiceMessagePlayer(
                  audioUrl: fileUrl,
                  isMe: isMe,
                  duration: message['audioDuration'] as int?,
                )
              else if (isImage)
                _buildImage(context, fileUrl, fileName, onLongPress)
              else
                _buildFile(context, fileUrl, fileName, message, onLongPress),
              if (text.isNotEmpty) const SizedBox(height: 8),
            ],
            // Text content
            if (text.isNotEmpty && !isDeleted)
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                  ),
                  textAlign: isMe ? TextAlign.right : TextAlign.left,
                ),
              ),
            if (isDeleted)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Message deleted',
                    style: TextStyle(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            // Footer (time, edited, status)
            if (!isDeleted)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    createdAt,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                    ),
                  ),
                  if (edited) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, size: 12, color: Colors.white),
                    const SizedBox(width: 2),
                    const Text(
                      '(edited)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    tickWidget(message),
                    const SizedBox(width: 4),
                    Text(
                      statusText(message),
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor(statusText(message)),
                        fontStyle: statusText(message) == 'seen'
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
  
  static Widget _buildImage(BuildContext context, String fileUrl, String? fileName, Function(String) onLongPress) {
    final imageSize = Responsive.getResponsiveValue(
      context,
      mobile: 200.0,
      tablet: 250.0,
      desktop: 300.0,
    );
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(fileName ?? 'Image')),
              body: Center(
                child: InteractiveViewer(
                  child: Image.network(
                    fileUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      size: 64,
                      color: Colors.white,
                    ),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
        child: Image.network(
          fileUrl,
          width: imageSize,
          height: imageSize,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: imageSize,
            height: imageSize,
            color: Colors.grey[800],
            child: const Icon(
              Icons.broken_image,
              size: 48,
              color: Colors.white54,
            ),
          ),
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: imageSize,
              height: imageSize,
              color: Colors.grey[800],
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
            );
          },
      ),
    );
  }
  
  static Widget _buildFile(BuildContext context, String fileUrl, String? fileName, Map<String, dynamic> message, Function(String) onLongPress) {
    Future<void> _open() async {
      final uri = Uri.tryParse(fileUrl);
      if (uri == null) return;
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open file')),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }

    return InkWell(
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FileService().getFileIcon(fileName),
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName ?? 'File',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message['fileSize'] != null)
                    Text(
                      FileService().formatFileSize(
                        int.tryParse(message['fileSize'].toString()) ?? 0,
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: _open,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}


