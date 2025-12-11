import 'package:flutter/material.dart';

/// Setting Item Widget
/// A reusable ListTile for settings with various configurations
class SettingItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final Color? iconColor;

  const SettingItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.iconColor,
  });

  /// Create a switch setting item
  factory SettingItem.switch_({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool showDivider = true,
    Color? iconColor,
  }) {
    return SettingItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
      ),
      showDivider: showDivider,
      iconColor: iconColor,
    );
  }

  /// Create a navigation setting item
  factory SettingItem.navigation({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    String? value,
    bool showDivider = true,
    Color? iconColor,
  }) {
    return SettingItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) ...[
            Text(
              value,
              style: TextStyle(
                color: iconColor ?? Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            Icons.chevron_right,
            color: Colors.grey,
          ),
        ],
      ),
      onTap: onTap,
      showDivider: showDivider,
      iconColor: iconColor,
    );
  }

  /// Create a destructive action item (red)
  factory SettingItem.destructive({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool showDivider = true,
  }) {
    return SettingItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      showDivider: showDivider,
      iconColor: Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            icon,
            color: iconColor ?? colorScheme.primary,
          ),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle!) : null,
          trailing: trailing,
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 56),
      ],
    );
  }
}

