import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import '../video_player_widget.dart';
import '../voice_message_player.dart';

/// Reply header bubble to show the original sender and text/image
/// inside a chat message, with a green left border (WhatsApp-style).
/// Viber-style: Tappable to open/play the replied content.
/// Audio messages play inline without dialog.
class ReplyBubble extends StatefulWidget {
  final String senderName;
  final String messageText;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? audioDuration;

  const ReplyBubble({
    super.key,
    required this.senderName,
    required this.messageText,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.audioDuration,
  });

  @override
  State<ReplyBubble> createState() => _ReplyBubbleState();
}

class _ReplyBubbleState extends State<ReplyBubble> {

  @override
  Widget build(BuildContext context) {
    // WhatsApp-style green colors
    const Color barColor = Color(0xFF25D366); // WhatsApp green
    const Color backgroundColor = Color(0xFFE7FCE3); // light green background
    const Color nameColor = Color(0xFF128C7E); // WhatsApp name green
    
    // Debug logging
    debugPrint('🖼️ ReplyBubble: fileType=${widget.fileType}, fileUrl=${widget.fileUrl}, fileName=${widget.fileName}, messageText=${widget.messageText}');
    
    final isImage = widget.fileType == 'image' && widget.fileUrl != null && widget.fileUrl!.isNotEmpty;
    final isVideo = widget.fileType == 'video' && widget.fileUrl != null && widget.fileUrl!.isNotEmpty;
    final isAudio = (widget.fileType == 'audio' || widget.fileType == 'voice') && widget.fileUrl != null && widget.fileUrl!.isNotEmpty;
    final isFile = widget.fileType != null && widget.fileType != 'image' && widget.fileType != 'video' && widget.fileType != 'audio' && widget.fileType != 'voice' && widget.fileUrl != null && widget.fileUrl!.isNotEmpty;
    
    debugPrint('🖼️ ReplyBubble: isImage=$isImage, isVideo=$isVideo, isAudio=$isAudio, isFile=$isFile');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(
            color: barColor,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.senderName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: nameColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (isImage)
                  // Show image thumbnail - tappable to open full screen
                  GestureDetector(
                    onTap: () => _openImage(context, widget.fileUrl!, widget.fileName),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: widget.fileUrl!,
                              width: 120,
                              height: 80,
                              fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 120,
                          height: 80,
                          color: Colors.grey[300],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 120,
                          height: 80,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else if (isVideo)
                  // Show video preview with first frame thumbnail - tappable to play video
                  GestureDetector(
                    onTap: () => _playVideo(context, widget.fileUrl!, widget.fileName),
                    child: _VideoThumbnail(
                      videoUrl: widget.fileUrl!,
                      width: 120,
                      height: 80,
                    ),
                  )
                else if (isAudio)
                  // Show audio message player inline - plays directly without dialog (Viber-style)
                  VoiceMessagePlayer(
                    audioUrl: widget.fileUrl!,
                    isMe: false, // Reply preview, so not "me"
                    duration: widget.audioDuration,
                  )
                else if (isFile)
                  // Show file indicator
                  Row(
                    children: [
                      const Icon(Icons.attach_file, size: 16, color: Colors.black87),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.fileName ?? 'File',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else if (widget.messageText.isNotEmpty)
                  // Show text
                  Text(
                    widget.messageText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }
  
  /// Open image in full screen viewer (Viber-style)
  void _openImage(BuildContext context, String imageUrl, String? fileName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(fileName ?? 'Image'),
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// Play video in full screen video player (Viber-style)
  /// Opens full screen with play button - user must press play to watch
  void _playVideo(BuildContext context, String videoUrl, String? fileName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenVideoPlayerPage(
          videoUrl: videoUrl,
          fileName: fileName,
        ),
      ),
    );
  }
  
}

/// Lightweight widget to show video thumbnail (first frame) in reply bubble
class _VideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final double width;
  final double height;

  const _VideoThumbnail({
    required this.videoUrl,
    required this.width,
    required this.height,
  });

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeThumbnail();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeThumbnail() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller!.initialize();
      
      // Seek to the beginning to show first frame
      await _controller!.seekTo(Duration.zero);
      // Play briefly to decode first frame, then pause
      await _controller!.play();
      await Future.delayed(const Duration(milliseconds: 200));
      await _controller!.pause();
      await _controller!.seekTo(Duration.zero);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading video thumbnail: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey[400],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Video thumbnail (first frame)
          if (_isInitialized && _controller != null && _controller!.value.isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            )
          else if (_hasError)
            Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey[400],
              child: const Icon(
                Icons.videocam,
                color: Colors.grey,
                size: 32,
              ),
            )
          else
            Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey[400],
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
            ),
          // Play icon overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Center(
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),
          // Video icon in corner
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Icon(
                Icons.videocam,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full screen video player page that shows video with play button
/// User must press play button to start watching (Viber-style)
/// Made public so it can be used from chat_page.dart
class FullScreenVideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String? fileName;

  const FullScreenVideoPlayerPage({
    super.key,
    required this.videoUrl,
    this.fileName,
  });

  @override
  State<FullScreenVideoPlayerPage> createState() => _FullScreenVideoPlayerPageState();
}

class _FullScreenVideoPlayerPageState extends State<FullScreenVideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _hasError = false;
  bool _showControls = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _positionTimer;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller!.initialize();
      
      // Seek to beginning to show first frame
      await _controller!.seekTo(Duration.zero);
      
      // Listen to player state changes
      _controller!.addListener(_onPlayerStateChanged);
      
      // Listen to duration changes
      _controller!.addListener(_onVideoChanged);
      
      // Start position timer
      _startPositionTimer();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
          _duration = _controller!.value.duration;
          _showControls = true;
        });
        _startHideControlsTimer();
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_controller != null && _controller!.value.isInitialized && mounted) {
        setState(() {
          _position = _controller!.value.position;
          _duration = _controller!.value.duration;
        });
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isPlaying) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _onPlayerStateChanged() {
    if (_controller != null && mounted) {
      setState(() {
        _isPlaying = _controller!.value.isPlaying;
      });
      if (_isPlaying) {
        _startHideControlsTimer();
      }
    }
  }

  void _onVideoChanged() {
    if (_controller != null && mounted) {
      setState(() {
        _duration = _controller!.value.duration;
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _rewind15Seconds() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final newPosition = _position - const Duration(seconds: 15);
    _controller!.seekTo(newPosition < Duration.zero ? Duration.zero : newPosition);
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _fastForward15Seconds() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final newPosition = _position + const Duration(seconds: 15);
    _controller!.seekTo(newPosition > _duration ? _duration : newPosition);
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.fileName ?? 'Video'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video player
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              )
            else if (_hasError)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.white54,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Error loading video',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            else if (_isInitialized && _controller != null && _controller!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            
            // Controls overlay (semi-transparent dark background)
            if (_showControls && _isInitialized && !_hasError)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // Center controls: Rewind, Play, Fast Forward
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Rewind 15 seconds button
                          _ControlButton(
                            label: '15',
                            onTap: _rewind15Seconds,
                            isRewind: true,
                          ),
                          const SizedBox(width: 24),
                          // Main play/pause button
                          GestureDetector(
                            onTap: _togglePlayPause,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.grey[800]!.withOpacity(0.8),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Fast forward 15 seconds button
                          _ControlButton(
                            label: '15',
                            onTap: _fastForward15Seconds,
                            isRewind: false,
                          ),
                        ],
                      ),
                    ),
                    
                    // Bottom controls: Title, progress bar, time
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.8),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Video title
                            Text(
                              widget.fileName ?? 'Video',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Progress bar (tappable to seek)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return GestureDetector(
                                  onTapDown: (details) {
                                    if (_controller != null && _controller!.value.isInitialized && _duration.inMilliseconds > 0) {
                                      final x = details.localPosition.dx;
                                      final width = constraints.maxWidth;
                                      final percentage = (x / width).clamp(0.0, 1.0);
                                      final newPosition = Duration(
                                        milliseconds: (_duration.inMilliseconds * percentage).round(),
                                      );
                                      _controller!.seekTo(newPosition);
                                      setState(() {
                                        _showControls = true;
                                      });
                                      _startHideControlsTimer();
                                    }
                                  },
                                  child: Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Stack(
                                      children: [
                                        // Progress indicator
                                        if (_duration.inMilliseconds > 0)
                                          FractionallySizedBox(
                                            widthFactor: (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            // Time display
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Current time / Total duration
                                Text(
                                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Control button widget for rewind/fast forward
class _ControlButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isRewind;

  const _ControlButton({
    required this.label,
    required this.onTap,
    required this.isRewind,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey[800]!.withOpacity(0.8),
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Use fast_forward icon for both, rotate 180 degrees for rewind
            Transform.rotate(
              angle: isRewind ? 3.14159 : 0, // 180 degrees for rewind, 0 for forward
              child: Icon(
                Icons.fast_forward,
                color: Colors.white,
                size: 28,
              ),
            ),
            Positioned(
              bottom: 8,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


