import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Avatar widget with online status indicator
/// Shows a green circle at the bottom-right when user is online
/// Shows a red circle at the bottom-right when user is inactive/offline
class AvatarWithStatus extends StatelessWidget {
  final String? avatarUrl;
  final String? fallbackText;
  final double radius;
  final bool isOnline;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Key? imageKey;
  final bool showOfflineIndicator; // Whether to show red indicator when offline

  const AvatarWithStatus({
    super.key,
    this.avatarUrl,
    this.fallbackText,
    this.radius = 25.0,
    this.isOnline = false,
    this.backgroundColor,
    this.foregroundColor,
    this.imageKey,
    this.showOfflineIndicator = true, // Show red indicator when offline by default
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primaryContainer;
    final fgColor = foregroundColor ?? theme.colorScheme.onPrimaryContainer;
    
    // Calculate indicator size based on avatar size
    final indicatorSize = radius * 0.45; // ~45% of avatar radius (increased for better visibility)
    final indicatorBorderWidth = 2.0;
    final indicatorOffset = radius * 0.12; // Position from edge (slightly adjusted for larger indicator)

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Avatar
        ClipOval(
          child: avatarUrl != null && avatarUrl!.isNotEmpty
              ? CachedNetworkImage(
                  key: imageKey,
                  imageUrl: avatarUrl!,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => _buildFallbackAvatar(
                    context,
                    bgColor,
                    fgColor,
                  ),
                  placeholder: (context, url) => _buildPlaceholderAvatar(
                    context,
                    bgColor,
                  ),
                )
              : _buildFallbackAvatar(context, bgColor, fgColor),
        ),
        // Status indicator (green for online, red for offline)
        if (isOnline || showOfflineIndicator)
          Positioned(
            right: -indicatorOffset,
            bottom: -indicatorOffset,
            child: Container(
              width: indicatorSize,
              height: indicatorSize,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: indicatorBorderWidth,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFallbackAvatar(
    BuildContext context,
    Color bgColor,
    Color fgColor,
  ) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      child: fallbackText != null && fallbackText!.isNotEmpty
          ? Text(
              fallbackText!,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.6,
              ),
            )
          : Icon(
              Icons.person,
              size: radius * 0.8,
            ),
    );
  }

  Widget _buildPlaceholderAvatar(BuildContext context, Color bgColor) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      child: SizedBox(
        width: radius,
        height: radius,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

