// lib/call_page.dart — UI/animation-focused makeover only
// NOTE: Signaling/WebRTC methods and flows remain unchanged. This patch
// only improves visuals, layout and micro-interactions.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'auth_store.dart';
import 'socket_service.dart';
import 'services/call_log_service.dart';
import 'models/call_log.dart';
import 'api.dart';
import 'chat_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum CallPhase { ringing, connecting, active, ended }

class CallPage extends StatefulWidget {
  final String peerId;
  final String peerName;
  final bool outgoing;

  // incoming only – navigator မှာ push လုပ်တဲ့အခါ ဖြည့်ပေးဖို့
  final String? initialCallId;
  final Map<String, dynamic>? initialOffer;

  // video call on/off (default: true = video call)
  final bool video;

  const CallPage({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.outgoing,
    this.initialCallId,
    this.initialOffer,
    this.video = true,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _WavesPainter extends CustomPainter {
  final double progress;
  _WavesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withOpacity(.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const waves = 3;
    for (int i = 0; i < waves; i++) {
      final p = ((progress + i / waves) % 1.0);
      final radius = lerpDouble(40, size.shortestSide * .6, p)!;
      paint.color = Colors.white.withOpacity((1 - p) * .12);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavesPainter oldDelegate) =>
      oldDelegate.progress != progress;

  double? lerpDouble(num a, num b, double t) => a + (b - a) * t;
}

class _CallPageState extends State<CallPage> with TickerProviderStateMixin {
  // Signaling
  String? _myId;
  String? _callId;
  
  // Call tracking
  DateTime? _callStartTime;
  bool _callAccepted = false;
  String? _peerEmail;
  String? _peerAvatarUrl;
  bool _callLogged = false; // Prevent duplicate logging

  // WebRTC
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  // UI / state
  CallPhase _phase = CallPhase.ringing;
  bool _micOn = true;
  bool _camOn = true; // for video
  bool _speakerOn = true;
  bool _frontCamera = true;
  
  // Call duration timer
  Timer? _callDurationTimer;
  Duration _callDuration = Duration.zero;
  
  // Call timeout timer (for unanswered calls)
  Timer? _callTimeoutTimer;
  static const Duration _callTimeoutDuration = Duration(seconds: 60); // 60 seconds timeout

  // STUN/TURN
  final Map<String, dynamic> _iceConfig = const {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      // {'urls':'turn:YOUR_TURN:3478','username':'u','credential':'p'},
    ],
  };

  // --- Animation controllers (UI only) -------------------------------------
  late final AnimationController
  _ringPulse; // accept/reject pulse while ringing
  late final AnimationController _titleBlink; // subtle connecting blink
  late final AnimationController _fabNudge; // small nudge on primary button

  // Draggable local preview position
  final Offset _pipOffset = const Offset(12, 12);

  // ---- lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Hide system status bar completely - use manual mode to hide only status bar
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom], // Only show navigation bar, hide status bar completely
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
      ),
    );

    _ringPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: .94,
      upperBound: 1.06,
    )..repeat(reverse: true);

    _titleBlink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _fabNudge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _boot();
  }

  @override
  void dispose() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    
    _ringPulse.dispose();
    _titleBlink.dispose();
    _fabNudge.dispose();
    _callDurationTimer?.cancel();
    _callTimeoutTimer?.cancel();

    SocketService.I.off('call:ringing', _onRinging);
    SocketService.I.off('call:answer', _onAnswer);
    SocketService.I.off('call:candidate', _onRemoteCandidate);
    SocketService.I.off('call:declined', _onDeclined);
    SocketService.I.off('call:ended', _onEnded);

    _pc?.close();
    _localStream?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }
  
  void _startCallDurationTimer() {
    if (_callStartTime == null) return;
    _callDurationTimer?.cancel();
    _callDuration = Duration.zero;
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_callStartTime != null && _phase == CallPhase.active) {
        setState(() {
          _callDuration = DateTime.now().difference(_callStartTime!);
        });
      } else {
        timer.cancel();
      }
    });
  }
  
  /// Start timeout timer for unanswered calls
  void _startCallTimeout() {
    // Cancel any existing timeout timer
    _callTimeoutTimer?.cancel();
    
    // Start new timeout timer
    _callTimeoutTimer = Timer(_callTimeoutDuration, () {
      // Check if call is still ringing and not accepted
      if (mounted && _phase == CallPhase.ringing && !_callAccepted && !_callLogged) {
        debugPrint('Call timeout: call was not answered within ${_callTimeoutDuration.inSeconds} seconds');
        
        // Determine the correct status based on call direction
        // For outgoing calls: cancelled (caller cancelled/no answer)
        // For incoming calls: missed (receiver missed the call)
        final status = widget.outgoing ? CallStatus.cancelled : CallStatus.missed;
        
        // Notify the other party that the call has ended due to timeout
        if (_callId != null) {
          SocketService.I.emit('call:hangup', {'callId': _callId});
        }
        
        // Log the call with the appropriate status
        _logCallEnded(status).then((_) {
          // Update UI and end the call
          if (mounted) {
            setState(() => _phase = CallPhase.ended);
            _toast(widget.outgoing ? 'Call not answered' : 'Missed call');
            
            // Wait a moment to show the message, then close
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                _endLocal(skipLogging: true); // Skip logging since we already logged
              }
            });
          }
        });
      }
    });
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ---- setup ---------------------------------------------------------------

  Future<void> _boot() async {
    final u = await AuthStore.getUser();
    _myId = u?['id']?.toString();

    // Load peer profile info for call log
    await _loadPeerProfile();

    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Open media (camera opens for all video calls, but UI won't show it for incoming during ringing)
    await _openMedia();
    
    // Track call start
    _callStartTime = DateTime.now();

    // PeerConnection
    _pc = await createPeerConnection(_iceConfig);

    // add local tracks
    if (_localStream != null) {
    for (final t in _localStream!.getTracks()) {
      await _pc!.addTrack(t, _localStream!);
      }
    }

    // remote tracks
    _pc!.onTrack = (RTCTrackEvent ev) async {
      debugPrint('=== onTrack event ===');
      debugPrint('Track kind: ${ev.track.kind}');
      debugPrint('Streams: ${ev.streams.length}');
      
      if (ev.streams.isNotEmpty) {
        _remoteStream = ev.streams.first;
        _remoteRenderer.srcObject = _remoteStream;
        
        debugPrint('Remote stream ID: ${_remoteStream?.id}');
        debugPrint('Video tracks: ${_remoteStream?.getVideoTracks().length}');
        debugPrint('Audio tracks: ${_remoteStream?.getAudioTracks().length}');
        
        // Ensure video tracks are enabled
        for (final track in _remoteStream!.getVideoTracks()) {
          track.enabled = true;
          debugPrint('Video track: id=${track.id}, enabled=${track.enabled}');
        }
        
        // Force UI update - try multiple times to ensure it renders
        if (mounted) {
          setState(() {
            debugPrint('State updated - remote video stream received');
          });
          // Also update after delays to ensure renderer is ready
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              setState(() {
                debugPrint('First delayed update for remote video');
              });
            }
          });
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                debugPrint('Second delayed update for remote video');
              });
            }
          });
        }
      } else {
        debugPrint('Track without stream: ${ev.track.kind}');
      }
      if (mounted) {
        setState(() {});
      }
    
    };

    // ICE
    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (_callId == null) return;
      SocketService.I.emit('call:candidate', {
        'callId': _callId,
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };

    // audio route (video calls usually speaker on)
    await Helper.setSpeakerphoneOn(_speakerOn);

    // register signaling (⚠️ call:incoming ကို မနားထောင်!)
    SocketService.I.on('call:ringing', _onRinging);
    SocketService.I.on('call:answer', _onAnswer);
    SocketService.I.on('call:candidate', _onRemoteCandidate);
    SocketService.I.on('call:declined', _onDeclined);
    SocketService.I.on('call:ended', _onEnded);

    // flows
    if (widget.outgoing) {
      await _startOutgoing();
    } else {
      // incoming → use initial offer
      _callId = widget.initialCallId;
      final sdp = widget.initialOffer ?? const {};
      if (_callId == null || sdp.isEmpty) {
        _toast('No call session'); // defensive
        _endLocal(endRemote: false);
        return;
      }
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      setState(() => _phase = CallPhase.ringing);
      
      // Start timeout timer for incoming calls
      _startCallTimeout();
    }
  }

  Future<void> _openMedia() async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': widget.video
          ? {
              'facingMode': _frontCamera ? 'user' : 'environment',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localRenderer.srcObject = _localStream;
  }

  // ---- signaling (handlers) -----------------------------------------------

  void _onRinging(dynamic data) {
    // for caller; server echoes that callee is ringing + returns callId
    final m = Map<String, dynamic>.from(data ?? {});
    final to = (m['to'] ?? '').toString();
    if (to != widget.peerId) return;
    final cid = (m['callId'] ?? '').toString();
    if (cid.isNotEmpty) _callId = cid;
    setState(() => _phase = CallPhase.ringing);
    
    // Start timeout timer for outgoing calls
    if (widget.outgoing) {
      _startCallTimeout();
    }
  }

  Future<void> _onAnswer(dynamic data) async {
    // for caller; callee accepted and sent answer SDP
    final m = Map<String, dynamic>.from(data ?? {});
    final from = (m['from'] ?? '').toString();
    if (from != widget.peerId) return;
    final sdp = Map<String, dynamic>.from(m['sdp'] ?? {});
    if (sdp.isEmpty) return;
    await _pc?.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'], sdp['type']),
    );
    setState(() {
      _phase = CallPhase.active;
      _callAccepted = true;
    });
    // Cancel timeout timer since call was answered
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    // Start call duration timer
    _startCallDurationTimer();
  }

  Future<void> _onRemoteCandidate(dynamic data) async {
    final m = Map<String, dynamic>.from(data ?? {});
    final from = (m['from'] ?? '').toString();
    if (from != widget.peerId) return;
    final c = Map<String, dynamic>.from(m['candidate'] ?? {});
    if (c.isEmpty) return;
    await _pc?.addCandidate(
      RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
    );
  }

  void _onDeclined(dynamic _) {
    if (_callLogged) return; // Prevent duplicate handling
    // Cancel timeout timer since call was declined
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    setState(() => _phase = CallPhase.ended);
    _toast('Call declined');
    
    // Log the call
    _logCallEnded(CallStatus.rejected).then((_) {
      // Wait a moment to show the message, then close
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          _endLocal(skipLogging: true); // Skip logging since we already logged
        }
      });
    });
  }

  void _onEnded(dynamic _) {
    if (_callLogged) return; // Prevent duplicate handling
    // Cancel timeout timer since call was ended
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    setState(() => _phase = CallPhase.ended);
    
    // Determine the correct status:
    // - If call was accepted and active: completed
    // - If call was never accepted (timeout/no answer): missed (incoming) or cancelled (outgoing)
    final status = _callAccepted 
        ? CallStatus.completed 
        : (widget.outgoing ? CallStatus.cancelled : CallStatus.missed);
    
    _toast(status == CallStatus.completed 
        ? 'Call ended' 
        : (widget.outgoing ? 'Call not answered' : 'Missed call'));
    
    // Log the call with the appropriate status
    _logCallEnded(status).then((_) {
      // Wait a moment to show the message, then close
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          _endLocal(skipLogging: true); // Skip logging since we already logged
        }
      });
    });
  }

  // ---- flows ---------------------------------------------------------------

  Future<void> _startOutgoing() async {
    setState(() => _phase = CallPhase.connecting);

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.video ? 1 : 0,
    });
    await _pc!.setLocalDescription(offer);

    SocketService.I.emit('call:invite', {
      'to': widget.peerId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
      'kind': widget.video ? 'video' : 'audio', // ⬅️ Tell backend it's a video call
    });
    debugPrint('Call invite sent: to=${widget.peerId}, kind=${widget.video ? 'video' : 'audio'}');

    // server will emit `call:ringing` with callId back
    setState(() => _phase = CallPhase.ringing);
    
    // Start timeout timer for outgoing calls
    _startCallTimeout();
  }

  Future<void> _accept() async {
    if (_callId == null) {
      _toast('No call session');
      return;
    }
    // Cancel timeout timer since call was accepted
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    setState(() {
      _phase = CallPhase.connecting;
      _callAccepted = true;
    });

    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.video ? 1 : 0,
    });
    await _pc!.setLocalDescription(answer);

    SocketService.I.emit('call:answer', {
      'callId': _callId,
      'accept': true,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });

    setState(() {
      _phase = CallPhase.active;
      _callAccepted = true;
      debugPrint('Receiver accepted call - phase: $_phase, video: ${widget.video}');
    });
    // Start call duration timer
    _startCallDurationTimer();
  }

  Future<void> _reject() async {
    if (_callLogged) return; // Prevent duplicate handling
    // Cancel timeout timer since call was rejected
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    if (_callId != null) {
      SocketService.I.emit('call:answer', {'callId': _callId, 'accept': false});
    }
    _logCallEnded(CallStatus.rejected);
    _endLocal(skipLogging: true); // Skip logging since we already logged
  }

  Future<void> _hangup() async {
    if (_callLogged) return; // Prevent duplicate handling
    // Cancel timeout timer since call was hung up
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    if (_callId != null) {
      SocketService.I.emit('call:hangup', {'callId': _callId});
    }
    _logCallEnded(_callAccepted ? CallStatus.completed : CallStatus.cancelled);
    _endLocal(skipLogging: true); // Skip logging since we already logged
  }

  void _endLocal({bool endRemote = true, bool skipLogging = false}) {
    // Cancel timeout timer
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    
    // If call was ringing but never accepted, log as missed (for incoming) or cancelled (for outgoing)
    if (!skipLogging && _callStartTime != null && !_callAccepted && _phase == CallPhase.ringing && !_callLogged) {
      final status = widget.outgoing ? CallStatus.cancelled : CallStatus.missed;
      _logCallEnded(status);
    }
    
    // Clean up resources
    try {
      _pc?.close();
      _localStream?.dispose();
    } catch (_) {}
    _pc = null;
    _localStream = null;
    
    // Navigate back
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
  
  /// Load peer profile information
  Future<void> _loadPeerProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/users/by-ids?ids=${widget.peerId}'),
        headers: await authHeaders(),
      );
      if (response.statusCode == 200) {
        final map = Map<String, dynamic>.from(jsonDecode(response.body));
        final peerData = map[widget.peerId];
        if (peerData != null) {
          _peerEmail = peerData['email']?.toString();
          _peerAvatarUrl = peerData['avatarUrl']?.toString();
        }
      }
    } catch (e) {
      debugPrint('Error loading peer profile: $e');
    }
  }
  
  /// Log call when it ends
  Future<void> _logCallEnded(CallStatus status) async {
    if (_callStartTime == null || _callLogged) {
      debugPrint('Skipping duplicate call log: startTime=$_callStartTime, logged=$_callLogged');
      return;
    }
    _callLogged = true; // Prevent duplicate logging
    
    final endTime = DateTime.now();
    final duration = endTime.difference(_callStartTime!);
    
    // Use server-provided callId if available, otherwise generate one
    // The callId should be the same for both participants (from server)
    final callId = _callId ?? '${_myId}_${widget.peerId}_${_callStartTime!.millisecondsSinceEpoch}';
    
    debugPrint('Logging call: id=$callId, status=$status, duration=${duration.inSeconds}s, type=${widget.outgoing ? "outgoing" : "incoming"}');
    
    // Only include duration for completed calls
    final callDuration = (status == CallStatus.completed && duration.inSeconds > 0) 
        ? duration 
        : null;
    
    await CallLogService.logCall(
      callId: callId,
      peerId: widget.peerId,
      peerName: widget.peerName,
      peerEmail: _peerEmail,
      peerAvatarUrl: _peerAvatarUrl,
      type: widget.outgoing ? CallType.outgoing : CallType.incoming,
      status: status,
      startTime: _callStartTime!,
      endTime: endTime,
      duration: callDuration,
      isVideoCall: widget.video,
    );
  }

  // ---- controls ------------------------------------------------------------

  void _toggleMic() {
    _micOn = !_micOn;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _micOn);
    setState(() {});
  }

  Future<void> _toggleCam() async {
    if (!widget.video) return;
    _camOn = !_camOn;
    for (final t in _localStream?.getVideoTracks() ?? []) {
      t.enabled = _camOn;
    }
    setState(() {});
  }

  Future<void> _switchCamera() async {
    if (!widget.video) return;
    _frontCamera = !_frontCamera;
    final videoTrack = _localStream?.getVideoTracks().firstOrDefault;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
    }
    setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
    setState(() {});
  }

  // ---- ui ------------------------------------------------------------------

  Widget _buildStatusBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final iconSize = isSmallScreen ? 16.0 : 18.0;
    final fontSize = isSmallScreen ? 14.0 : 16.0;
    final smallFontSize = isSmallScreen ? 12.0 : 14.0;
    final isCaller = widget.outgoing;
    
    return Column(
      children: [
        // Top status bar with time, camera notch area, battery
        Container(
      padding: EdgeInsets.only(
            top: 8, // Fixed padding since system status bar is hidden
        left: isSmallScreen ? 8 : 16,
        right: isSmallScreen ? 8 : 16,
            bottom: 4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
              // Left side: Time (and icons for incoming)
              Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                  Text(
                      _getCurrentTime(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (!isCaller) ...[
                  const SizedBox(width: 4),
                    const Icon(Icons.security, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                    Icon(Icons.settings, color: Colors.white, size: iconSize),
                  ],
                ],
              ),
              // Center: Camera notch area - show time with gear for outgoing, empty for incoming
              if (isCaller)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getCurrentTime(),
                        style: TextStyle(
                          color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.settings, color: Colors.white, size: iconSize),
                ],
                )
              else
                const SizedBox(width: 80), // Spacer for camera notch
              // Right side: Signal, WiFi, Battery
              Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                  Icon(Icons.signal_cellular_alt, color: Colors.white, size: iconSize),
                  SizedBox(width: isSmallScreen ? 4 : 6),
                Icon(Icons.wifi, color: Colors.white, size: iconSize),
                  SizedBox(width: isSmallScreen ? 4 : 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '97%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: smallFontSize,
                    ),
                  ),
                ),
                SizedBox(width: isSmallScreen ? 2 : 4),
                Icon(Icons.battery_full, color: Colors.white, size: iconSize),
              ],
              ),
            ],
          ),
        ),
        // Second row: Time with shield, gear, copyright icons (matches image)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getCurrentTime(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.security, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Icon(Icons.settings, color: Colors.white, size: iconSize),
              const SizedBox(width: 6),
              // Copyright icon (C in circle)
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Center(
                  child: Text(
                    'C',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildAvatar() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade400, // Light grey background (matches image)
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: _peerAvatarUrl != null && _peerAvatarUrl!.isNotEmpty
          ? ClipOval(
              child: Image.network(
                _peerAvatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildAvatarPlaceholder(),
              ),
            )
          : _buildAvatarPlaceholder(),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade400, // Light grey circle (matches image)
      ),
      child: Icon(
        Icons.person,
        size: 120,
        color: Colors.blue.shade700, // Blue silhouette (matches image)
      ),
    );
  }
  
  // Check if remote video is available - simplified check
  bool _hasRemoteVideo() {
    try {
      final stream = _remoteRenderer.srcObject;
      if (stream == null) {
        return false;
      }
      final videoTracks = stream.getVideoTracks();
      // If there are video tracks, assume video is available (even if not yet enabled)
      return videoTracks.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking remote video: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCaller = widget.outgoing;
    debugPrint('Build: phase=$_phase, video=${widget.video}, isCaller=$isCaller, showingVideoUI=${widget.video && (_phase == CallPhase.active || _phase == CallPhase.connecting || (_phase == CallPhase.ringing && !isCaller))}');
    final statusText = switch (_phase) {
      CallPhase.ringing => widget.outgoing 
          ? (widget.video ? 'Video call Calling' : 'Calling')
          : (widget.video ? 'Video call incoming' : 'Incoming call'),
      CallPhase.connecting => widget.video ? 'Video call Connecting...' : 'Connecting...',
      CallPhase.active => 'IN CALL',
      CallPhase.ended => widget.outgoing ? 'CALL DECLINED' : 'CALL ENDED',
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(
        child: Container(
          width: double.infinity,
          height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
                const Color(0xFFB19CD9), // Light purple (matches image)
                const Color(0xFF87CEEB), // Light blue (matches image)
            ],
          ),
        ),
          child: Column(
            children: [
              // Main content area - Video call shows video feed, audio call shows avatar
              // Show video UI only when: video call is active OR connecting (NOT during incoming call ringing)
              Expanded(
                child: (widget.video && (_phase == CallPhase.active || _phase == CallPhase.connecting))
                    ? Stack(
                        children: [
                          // Remote video (full screen during active video call)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: const BoxDecoration(color: Colors.black),
                              child: (_remoteRenderer.srcObject != null)
                                      ? RTCVideoView(
                                          _remoteRenderer,
                                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                        )
                                      : Center(
                                          // Show placeholder if no remote video yet
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              _buildAvatar(),
                                              const SizedBox(height: 24),
                                              Text(
                                                widget.peerName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Connecting video...',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.7),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                            ),
                          ),
                          
                          // Top bar overlay for video calls (like the image)
                          // Show during active call or connecting
                          if (widget.video && (_phase == CallPhase.active || _phase == CallPhase.connecting))
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.6),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                                child: SafeArea(
                                  bottom: false,
                                  child: Stack(
                                    children: [
                                      // Left side: Back button
                                      Positioned(
                                        left: 0,
                                        child: IconButton(
                                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                                          onPressed: () => Navigator.of(context).pop(),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ),
                                      // Center: Caller name and duration (centered)
                                      Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              widget.peerName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            // Show call duration only during active call
                                            if (_phase == CallPhase.active)
                                              Text(
                                                _formatDuration(_callDuration),
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.8),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            // Show "Video call incoming" or "Incoming call" text during ringing
                                            if (_phase == CallPhase.ringing && !isCaller)
                                              Text(
                                                widget.video ? 'Video call incoming' : 'Incoming call',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.8),
                                                  fontSize: 14,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Right side: Menu button (only during active call)
                                      if (_phase == CallPhase.active)
                                        Positioned(
                                          right: 0,
                                          child: IconButton(
                                            icon: const Icon(Icons.more_vert, color: Colors.white),
                                            onPressed: () {
                                              // Show menu options
                                              _toast('Menu');
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          
                          // Local preview (fixed position bottom right - like the image)
                          // Only show during active call or connecting (for outgoing calls)
                          if (_phase == CallPhase.active || (_phase == CallPhase.connecting && isCaller && widget.video))
                            Positioned(
                              right: 16,
                              bottom: 120, // Above the control buttons
                              width: 110,
                              height: 150,
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: RTCVideoView(
                                        _localRenderer,
                                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                        mirror: _frontCamera,
                                      ),
                                    ),
                                  ),
                                  // Camera switch button (top right of local preview)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: _switchCamera,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.6),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.flip_camera_ios,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // For incoming calls: Show "Video call incoming" or "Incoming call" text above name
                          if (!isCaller && _phase == CallPhase.ringing) ...[
                                    Text(
                              widget.video ? 'Video call incoming' : 'Incoming call',
                                      style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                ),
                              ),
                            const SizedBox(height: 24),
                          ],
                          
                          // Caller name - Large white text (matches image)
                            Text(
                              widget.peerName,
                              style: const TextStyle(
                                color: Colors.white,
                              fontSize: 42,
                                fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              ),
                            ),
                          const SizedBox(height: 32),
                          
                          // Avatar - Large circular (matches image)
                          AnimatedScale(
                            scale: _phase == CallPhase.ringing
                                ? 0.95 + 0.05 * math.sin(_ringPulse.value * 2 * math.pi)
                                : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: _buildAvatar(),
                          ),
                          
                          // Status text below avatar (matches image)
                          const SizedBox(height: 24),
                            AnimatedBuilder(
                              animation: _titleBlink,
                              builder: (_, __) {
                                final blink = (_phase == CallPhase.connecting)
                                    ? (0.7 + 0.3 * (0.5 + 0.5 * math.sin(_titleBlink.value * 2 * math.pi)))
                                    : 1.0;
                                return Opacity(
                                  opacity: blink,
                                child: Text(
                                        statusText,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                    letterSpacing: 1.0,
                                              ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
              ),
              
              // Action buttons (for incoming calls during ringing phase) - matches right side screen
              if (!isCaller && _phase == CallPhase.ringing)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Accept and Decline buttons (row)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Accept button (left) - Green
                            ScaleTransition(
                              scale: _ringPulse,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.green,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.4),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Transform.rotate(
                                  angle: -0.5, // Rotate phone icon to point left (matches image)
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.call,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: _accept,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 80),
                            // Decline button (right) - Red
                            ScaleTransition(
                              scale: _ringPulse,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.4),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Transform.rotate(
                                  angle: 0.5, // Rotate phone icon to point left (matches image)
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.call_end,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: _reject,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              // Action buttons (for outgoing calls during ringing/connecting phase)
              else if (isCaller && (_phase == CallPhase.ringing || _phase == CallPhase.connecting))
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // End Call button (centered) - Red - Larger and more prominent
                        ScaleTransition(
                          scale: _ringPulse,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.5),
                                  blurRadius: 15,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _hangup,
                                borderRadius: BorderRadius.circular(36),
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    alignment: Alignment.center,
                                    child: Transform.rotate(
                                      angle: 0.5, // Rotate phone icon to point left (matches image)
                                      child: const Icon(
                                        Icons.call_end,
                                        color: Colors.white,
                                        size: 36,
                                      ),
                                    ),
                                  ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_phase == CallPhase.active || _phase == CallPhase.connecting)
                // Video call controls at bottom - flexible and responsive design
                SafeArea(
                  top: false,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width * 0.05, // 5% of screen width
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate flexible button sizes based on available width
                        final screenWidth = constraints.maxWidth;
                        final buttonCount = widget.video ? 4 : 3; // Speaker, Mute, Video (if video), End
                        final availableWidth = screenWidth * 0.85; // Account for padding
                        // Calculate size based on available space, with min/max constraints
                        final buttonSize = (availableWidth / (buttonCount + 1)).clamp(50.0, 70.0);
                        final endButtonSize = (buttonSize * 1.2).clamp(58.0, 75.0);
                        
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Speaker button
                            _buildFlexibleControlButton(
                              icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                              onTap: _toggleSpeaker,
                              active: _speakerOn,
                              size: buttonSize,
                            ),
                            
                            // Mute button
                            _buildFlexibleControlButton(
                              icon: _micOn ? Icons.mic : Icons.mic_off,
                              onTap: _toggleMic,
                              active: !_micOn,
                              size: buttonSize,
                            ),
                            
                            // Video toggle button (only for video calls)
                            if (widget.video)
                              _buildFlexibleControlButton(
                                icon: _camOn ? Icons.videocam : Icons.videocam_off,
                                onTap: _toggleCam,
                                active: _camOn,
                                size: buttonSize,
                              ),
                            
                            // End Call button - Red button (larger and prominent)
                            _buildFlexibleEndButton(
                              size: endButtonSize,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Video call control button (matching the image design)
  Widget _buildVideoCallControlButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(active ? 0.3 : 0.2),
          border: Border.all(
            color: Colors.white.withOpacity(active ? 0.8 : 0.5),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  // Flexible control button that adapts to screen size
  Widget _buildFlexibleControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
    bool active = false,
  }) {
    final iconSize = (size * 0.43).clamp(20.0, 28.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(active ? 0.3 : 0.2),
            border: Border.all(
              color: Colors.white.withOpacity(active ? 0.8 : 0.5),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
  }

  // Flexible end call button that adapts to screen size
  Widget _buildFlexibleEndButton({
    required double size,
  }) {
    final iconSize = (size * 0.5).clamp(24.0, 32.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _hangup,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.5),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Icons.call_end,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
  }

  // Viber-style control button (for active call controls)
  Widget _buildViberControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? activeColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active 
                  ? (activeColor ?? Colors.blue).withOpacity(0.2)
                  : Colors.white.withOpacity(0.2),
              border: Border.all(
                color: active 
                    ? (activeColor ?? Colors.blue)
                    : Colors.white.withOpacity(0.5),
                width: active ? 2 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: (activeColor ?? Colors.blue).withOpacity(0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: Icon(
              icon,
              color: active 
                  ? (activeColor ?? Colors.blue)
                  : Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Action button for the grid (Contact, Mute, etc.)
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool isBottomBar = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isBottomBar ? 48 : 56,
            height: isBottomBar ? 48 : 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: active ? Colors.blue.shade700 : Colors.blue.shade900,
              size: isBottomBar ? 24 : 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // keep icon API; add subtle glow when active
  Widget _roundIcon({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.white.withOpacity(.4),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  // ringing waves painter
  // purely visual; uses black background so only subtle lines appear over video
  // progress 0..1

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}

// small helper
extension _X on List<MediaStreamTrack> {
  MediaStreamTrack? get firstOrDefault => isEmpty ? null : first;
}

// helpers for pip drag bounds (prevent negative offsets during gesture)
double rightPaddingClamp(double v) => v;
double bottomPaddingClamp(double v) => v;
