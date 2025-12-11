import mongoose from 'mongoose';

/**
 * Call Service
 * Manages WebRTC call state and signaling
 * Uses database or Redis for persistence (optional)
 */
class CallService {
  constructor(io) {
    this.io = io;
    // In-memory call state (can be moved to Redis/database for scaling)
    this.activeCalls = new Map(); // callId -> { a, b, state, kind, startedAt, timer }
    this.userToCall = new Map(); // userId -> callId (for busy check)
  }

  /**
   * Generate unique call ID
   */
  newCallId() {
    return Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
  }

  /**
   * Create call invitation
   */
  async inviteCall(fromUserId, toUserId, sdp, kind = 'audio') {
    const from = String(fromUserId);
    const to = String(toUserId);
    
    // Check if either user is busy
    if (this.userToCall.has(from) || this.userToCall.has(to)) {
      return {
        success: false,
        error: 'busy',
        message: 'User is already in a call'
      };
    }
    
    const callId = this.newCallId();
    const session = {
      callId,
      a: from,
      b: to,
      state: 'ringing',
      kind,
      startedAt: new Date(),
      timer: null
    };
    
    this.activeCalls.set(callId, session);
    this.userToCall.set(from, callId);
    this.userToCall.set(to, callId);
    
    // Set timeout (40 seconds)
    session.timer = setTimeout(() => {
      const s = this.activeCalls.get(callId);
      if (s && s.state === 'ringing') {
        this.io.to(s.a).emit('call:ended', { callId, by: 'timeout' });
        this.io.to(s.b).emit('call:ended', { callId, by: 'timeout' });
        this.cleanupCall(callId);
      }
    }, 40000);
    
    // Send invitation
    this.sendToUser(to, 'call:incoming', {
      callId,
      from,
      sdp,
      kind
    });
    
    this.sendToUser(from, 'call:ringing', {
      callId,
      to,
      kind
    });
    
    return {
      success: true,
      callId
    };
  }

  /**
   * Answer call
   */
  async answerCall(callId, userId, accept, sdp) {
    const who = String(userId);
    const session = this.activeCalls.get(callId);
    
    if (!session) {
      return {
        success: false,
        error: 'not_found',
        message: 'Call not found'
      };
    }
    
    const { a: caller, b: callee, kind } = session;
    
    if (!accept) {
      // Call declined
      this.sendToUser(caller, 'call:declined', { callId, from: who });
      this.sendToUser(callee, 'call:declined', { callId, from: who });
      this.cleanupCall(callId);
      return { success: true, accepted: false };
    }
    
    if (!sdp?.type || !sdp?.sdp) {
      return {
        success: false,
        error: 'invalid_sdp',
        message: 'SDP is required'
      };
    }
    
    // Call accepted
    session.state = 'answered';
    if (session.timer) {
      clearTimeout(session.timer);
      session.timer = null;
    }
    
    this.sendToUser(caller, 'call:answer', {
      callId,
      from: callee,
      sdp,
      kind
    });
    
    return {
      success: true,
      accepted: true,
      callId
    };
  }

  /**
   * Relay ICE candidate
   */
  async relayCandidate(callId, userId, candidate) {
    const who = String(userId);
    const session = this.activeCalls.get(callId);
    
    if (!session) {
      return { success: false, error: 'not_found' };
    }
    
    const peer = who === session.a ? session.b : session.a;
    this.sendToUser(peer, 'call:candidate', {
      callId,
      from: who,
      candidate
    });
    
    return { success: true };
  }

  /**
   * Hangup call
   */
  async hangupCall(callId, userId) {
    const who = String(userId);
    const session = this.activeCalls.get(callId);
    
    if (!session) {
      return { success: false, error: 'not_found' };
    }
    
    const peer = who === session.a ? session.b : session.a;
    
    this.sendToUser(peer, 'call:ended', { callId, by: who });
    this.sendToUser(who, 'call:ended', { callId, by: who });
    
    this.cleanupCall(callId);
    
    return { success: true };
  }

  /**
   * Cleanup call state
   */
  cleanupCall(callId) {
    const session = this.activeCalls.get(callId);
    if (!session) return;
    
    if (session.timer) {
      clearTimeout(session.timer);
    }
    
    this.userToCall.delete(session.a);
    this.userToCall.delete(session.b);
    this.activeCalls.delete(callId);
  }

  /**
   * Get call state
   */
  getCall(callId) {
    return this.activeCalls.get(callId);
  }

  /**
   * Check if user is in a call
   */
  isUserInCall(userId) {
    return this.userToCall.has(String(userId));
  }

  /**
   * Send to user (helper)
   */
  sendToUser(userId, event, data) {
    // This will use io from socket handler
    // For now, we'll emit directly in socket handlers
    if (this.io) {
      this.io.to(String(userId)).emit(event, data);
    }
  }

  /**
   * Cleanup on user disconnect
   */
  handleUserDisconnect(userId) {
    const uid = String(userId);
    const callId = this.userToCall.get(uid);
    
    if (callId) {
      const session = this.activeCalls.get(callId);
      if (session) {
        const peer = uid === session.a ? session.b : session.a;
        if (this.io) {
          this.io.to(peer).emit('call:ended', { callId, by: 'disconnect' });
        }
      }
      this.cleanupCall(callId);
    }
  }
}

export default CallService;

