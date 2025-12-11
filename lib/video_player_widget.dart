// lib/video_player_widget.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String? fileName;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.fileName,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Automatically load video to show first frame thumbnail
    _initializePlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    if (_controller != null) return; // Already initializing or initialized
    
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      debugPrint('Initializing video player with URL: ${widget.videoUrl}');
      
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller!.initialize();
      
      debugPrint('Video initialized: duration=${_controller!.value.duration}, size=${_controller!.value.size}');
      
      // Ensure we're at the first frame to show thumbnail
      // The video player needs to be at position 0 to show the first frame
      if (_controller!.value.duration.inMilliseconds > 0) {
        await _controller!.seekTo(Duration.zero);
        // Play briefly to decode first frame, then pause
        _controller!.play();
        await Future.delayed(const Duration(milliseconds: 100));
        _controller!.pause();
        await _controller!.seekTo(Duration.zero);
      }
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
        debugPrint('Video player state updated: isInitialized=true');
      }
    } catch (e, stackTrace) {
      debugPrint('Error initializing video player: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fixed size for consistent display in chat (same as images)
    const double videoWidth = 280.0;
    const double videoHeight = 280.0;

    // Loading state - show while video is initializing
    if (_isLoading || !_isInitialized) {
      return Container(
        width: videoWidth,
        height: videoHeight,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    // Error state
    if (_hasError) {
      return Container(
        width: videoWidth,
        height: videoHeight,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.white54,
            ),
            const SizedBox(height: 8),
            const Text(
              'Error loading video',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _isInitialized = false;
                  _hasError = false;
                  _controller?.dispose();
                  _controller = null;
                });
                _initializePlayer();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Video loaded - show first frame thumbnail that opens full screen on tap
    if (_controller != null && _controller!.value.isInitialized) {
      final videoAspectRatio = _controller!.value.aspectRatio;
      final displayHeight = videoWidth / videoAspectRatio;
      final clampedHeight = displayHeight.clamp(200.0, 400.0);

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _FullScreenVideoPlayer(
                controller: _controller!,
                fileName: widget.fileName,
              ),
            ),
          );
        },
        child: Container(
          width: videoWidth,
          height: clampedHeight,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Video thumbnail (first frame)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: videoWidth,
                  height: clampedHeight,
                  color: Colors.black,
                  child: _controller!.value.size.width > 0
                      ? AspectRatio(
                          aspectRatio: videoAspectRatio,
                          child: VideoPlayer(_controller!),
                        )
                      : Container(
                          color: Colors.grey[900],
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
              ),
              // Large play button overlay (TikTok-style)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(
                  Icons.play_circle_filled,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              // Video file name at bottom
              if (widget.fileName != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.fileName!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Fallback
    return Container(
      width: videoWidth,
      height: videoHeight,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      ),
    );
  }
}

class _FullScreenVideoPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  final String? fileName;

  const _FullScreenVideoPlayer({
    required this.controller,
    this.fileName,
  });

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    // Auto-play video when opened in full screen
    if (widget.controller.value.isInitialized) {
      widget.controller.play();
    }
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
    });
    _startHideControlsTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.5),
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(
                widget.fileName ?? 'Video',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: widget.controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: widget.controller.value.aspectRatio,
                      child: VideoPlayer(widget.controller),
                    )
                  : const CircularProgressIndicator(
                      color: Colors.white,
                    ),
            ),
            if (_showControls)
              Positioned(
                bottom: 20,
                child: FloatingActionButton(
                  onPressed: _togglePlayPause,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  child: Icon(
                    widget.controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

