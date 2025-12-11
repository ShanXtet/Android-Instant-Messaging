// lib/emoji_picker_widget.dart
import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class EmojiPickerWidget extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;
  final VoidCallback onBackspace;

  const EmojiPickerWidget({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return EmojiPicker(
        onEmojiSelected: (category, emoji) {
          onEmojiSelected(emoji.emoji);
        },
        onBackspacePressed: onBackspace,
        config: Config(
        height: 250,
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            emojiSizeMax: 28 * (1.0),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          ),
          skinToneConfig: const SkinToneConfig(),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: Colors.grey.shade50,
          iconColorSelected: Theme.of(context).colorScheme.primary,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          enabled: false, // Disable bottom action bar to remove search button
        ),
      ),
    );
  }
}

