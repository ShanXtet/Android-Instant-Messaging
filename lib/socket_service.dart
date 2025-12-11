import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  SocketService._();
  static final I = SocketService._();

  IO.Socket? _s;
  final _handlers = <String, List<Function>>{};
  bool _isConnecting = false;
  bool _isConnected = false; // Track actual connection state (set only when onConnect fires)
  String? _currentBaseUrl;
  String? _currentToken;

  void connect({required String baseUrl, required String token}) {
    // If already connected with same credentials, don't reconnect
    if (_isConnected && _s?.connected == true && _currentBaseUrl == baseUrl && _currentToken == token) {
      return;
    }
    
    // Prevent duplicate connection attempts with same credentials
    if (_isConnecting && _currentBaseUrl == baseUrl && _currentToken == token) {
      return;
    }
    
    // Only disconnect if we're changing connection (different URL or token)
    final needsReconnect = _currentBaseUrl != baseUrl || _currentToken != token;
    if (needsReconnect && _s != null) {
      // Disconnect old socket only if credentials changed
      _s?.disconnect();
      _s?.dispose();
      _s = null;
      _isConnected = false; // Reset connection state when reconnecting
    }
    
    _isConnecting = true;
    _isConnected = false; // Reset connection state when starting new connection
    _currentBaseUrl = baseUrl;
    _currentToken = token;
    _s = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(20000) // 20 second connection timeout
          .disableAutoConnect()
          .build(),
    );

    for (final ev in [
      'chat_request',
      'chat_request_accepted',
      'chat_request_declined',
      'message',
      'message_deleted',
      'typing',
      'message_edited',
      'presence',
      'presence:initial',
      'delivered',
      'read_up_to',
      'call:incoming',
      'call:ringing',
      'call:answer',
      'call:candidate',
      'call:declined',
      'call:ended',
      'call:busy',
      'user_profile_updated',
    ]) {
      _s!.on(ev, (data) => _emit(ev, data));
    }

    _s!.onConnect((_) {
      _isConnecting = false;
      _isConnected = true; // Mark as truly connected when onConnect fires
      _emit('__connect__', null);
    });
    
    _s!.onDisconnect((reason) {
      _isConnecting = false;
      _isConnected = false; // Mark as disconnected
      _emit('__disconnect__', reason);
    });
    
    _s!.onError((e) {
      _isConnecting = false;
      _isConnected = false; // Mark as disconnected on error
      _emit('__error__', e);
    });
    
    _s!.onConnectError((e) {
      _isConnecting = false;
      _isConnected = false; // Mark as disconnected on connection error
      _emit('__error__', e);
    });
    
    _s!.connect();
  }

  void onReconnect(void Function() cb) {
    on('__connect__', (_) => cb());
  }

  void on(String event, Function(dynamic) cb) {
    _handlers.putIfAbsent(event, () => []).add(cb);
  }

  void off(String event, [Function(dynamic)? cb]) {
    if (!_handlers.containsKey(event)) return;
    if (cb == null) {
      _handlers.remove(event);
    } else {
      _handlers[event]!.remove(cb);
    }
  }

  void _emit(String ev, dynamic data) {
    final list = _handlers[ev];
    if (list == null) return;
    for (final cb in List<Function>.from(list)) {
      cb(data);
    }
  }

  void emit(String event, [dynamic data]) {
    _s?.emit(event, data);
  }

  void disconnect() {
    _s?.dispose();
    _s = null;
    _isConnecting = false;
    _isConnected = false; // Reset connection state
    _currentBaseUrl = null;
    _currentToken = null;
    _handlers.clear();
  }

  bool get isConnected => _isConnected && (_s?.connected == true);
}
