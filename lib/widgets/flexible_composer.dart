// lib/widgets/flexible_composer.dart
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../utils/responsive.dart';

class FlexibleComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onVoiceRecord;
  final VoidCallback? onAttach;
  final VoidCallback? onEmoji;
  final bool enabled;
  final bool isRecording;
  final bool showEmojiPicker;
  final String? recordingDuration;
  final VoidCallback? onCancelRecording;
  final bool hasText;
  final bool isEditing;
  final Widget? emojiPicker;

  const FlexibleComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.onVoiceRecord,
    this.onAttach,
    this.onEmoji,
    required this.enabled,
    this.isRecording = false,
    this.showEmojiPicker = false,
    this.recordingDuration,
    this.onCancelRecording,
    this.hasText = false,
    this.isEditing = false,
    this.emojiPicker,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final padding = Responsive.getPadding(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
            padding.left,
            0,
            padding.right,
            padding.bottom,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 12,
            vertical: isMobile ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: isDark 
                ? const Color(0xFF1E1E1E)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: isDark 
                ? Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                    width: 1,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withOpacity(.3)
                    : Colors.black.withOpacity(.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Voice record button
                  if (AppConfig.enableVoiceMessages && onVoiceRecord != null)
                    _buildVoiceButton(context, isMobile),
                  
                  // Attach button
                  if (AppConfig.enableFileSharing && onAttach != null)
                    IconButton(
                      tooltip: 'Attach file or photo',
                      icon: const Icon(Icons.attach_file),
                      color: enabled && !isRecording
                          ? theme.colorScheme.onSurface
                          : theme.disabledColor,
                      onPressed: enabled && !isRecording ? onAttach : null,
                      iconSize: isMobile ? 20 : 24,
                    ),
                  
                  // Text input
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 4 : 8,
                        vertical: isMobile ? 4 : 6,
                      ),
                      child: TextField(
                        controller: controller,
                        enabled: enabled && !isRecording,
                        onSubmitted: (_) => onSend(),
                        textInputAction: TextInputAction.send,
                        keyboardAppearance: isDark
                            ? Brightness.dark
                            : Brightness.light,
                        minLines: 1,
                        maxLines: isMobile ? 4 : 5,
                        decoration: InputDecoration(
                          hintText: isRecording
                              ? 'Recording...'
                              : (isEditing
                                  ? 'Edit message…'
                                  : 'Type a message…'),
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? theme.colorScheme.surface
                              : theme.colorScheme.surfaceContainerHighest.withOpacity(.6),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 16,
                            vertical: isMobile ? 10 : 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: isDark
                                ? BorderSide(
                                    color: theme.colorScheme.outline.withOpacity(0.3),
                                    width: 1,
                                  )
                                : BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: isDark
                                ? BorderSide(
                                    color: theme.colorScheme.outline.withOpacity(0.3),
                                    width: 1,
                                  )
                                : BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  
                  // Emoji button
                  if (AppConfig.enableEmojiPicker && onEmoji != null)
                    IconButton(
                      tooltip: 'Emoji',
                      icon: Icon(
                        showEmojiPicker
                            ? Icons.keyboard
                            : Icons.emoji_emotions_outlined,
                      ),
                      color: theme.colorScheme.onSurface,
                      onPressed: onEmoji,
                      iconSize: isMobile ? 20 : 24,
                    ),
                  
                  // Send/Stop button
                  _buildSendButton(context, isMobile),
                ],
              ),
              
              // Recording indicator
              if (isRecording && recordingDuration != null)
                _buildRecordingIndicator(context),
            ],
          ),
        ),
        
        // Emoji picker
        if (showEmojiPicker && emojiPicker != null) emojiPicker!,
      ],
    );
  }

  Widget _buildVoiceButton(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return GestureDetector(
      onLongPressStart: isRecording ? null : (_) => onVoiceRecord?.call(),
      onLongPressEnd: isRecording ? (_) => onVoiceRecord?.call() : null,
      child: Container(
        width: isMobile ? 40 : 48,
        height: isMobile ? 40 : 48,
        decoration: BoxDecoration(
          color: isRecording
              ? Colors.red.withOpacity(0.2)
              : (isDark
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.primary.withOpacity(0.1)),
          shape: BoxShape.circle,
        ),
      child: IconButton(
        tooltip: 'Hold to record voice',
        icon: Icon(isRecording ? Icons.mic : Icons.mic_none),
        color: isRecording
            ? Colors.red
              : (isDark
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.primary),
        iconSize: isMobile ? 20 : 24,
        onPressed: null,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);
    if (isRecording) {
      return IconButton(
        key: const ValueKey('stop'),
        icon: const Icon(Icons.stop, color: Colors.red),
        iconSize: isMobile ? 20 : 24,
        onPressed: onVoiceRecord,
      );
    }

    return AnimatedSwitcher(
      duration: AppConfig.shortAnimation,
      transitionBuilder: (c, a) => RotationTransition(
        turns: a,
        child: FadeTransition(opacity: a, child: c),
      ),
      child: IconButton(
        key: ValueKey(isEditing ? 'save' : 'send'),
        icon: Icon(isEditing ? Icons.check : Icons.send),
        color: hasText
            ? theme.colorScheme.primary
            : theme.disabledColor,
        iconSize: isMobile ? 20 : 24,
        onPressed: hasText ? onSend : null,
      ),
    );
  }

  Widget _buildRecordingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Text(
            recordingDuration ?? '0:00',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (onCancelRecording != null)
            TextButton(
              onPressed: onCancelRecording,
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}


