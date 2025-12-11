import jwt from 'jsonwebtoken';
import config from '../config/index.js';

/**
 * Socket.IO Handler
 * Integrates all services for real-time communication
 */
export default (io, services) => {
  const {
    messageService,
    presenceService,
    callService,
    notificationService
  } = services;

  // Set io reference for services that need it
  if (callService) {
    callService.io = io;
  }

  // Authentication middleware
  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.headers?.authorization?.replace('Bearer ', '');
      
      if (!token) {
        return next(new Error('unauthorized'));
      }

      const decoded = jwt.verify(token, config.jwtSecret, {
        algorithms: ['HS256']
      });

      // Support all token formats
      const userId = decoded.id || decoded.uid || decoded.userId || decoded._id;
      
      if (!userId) {
        return next(new Error('unauthorized'));
      }

      socket.data.uid = String(userId);
      socket.userId = String(userId);
      next();
    } catch (error) {
      console.error('❌ Socket auth error:', error.message);
      next(new Error('unauthorized'));
    }
  });

  io.on('connection', async (socket) => {
    const uid = socket.data.uid;
    const userId = socket.userId;

    console.log(`🟢 Socket connected: ${socket.id} (User: ${userId})`);

    // Join user room
    socket.join(userId);

    // Track presence
    if (presenceService) {
      const deviceInfo = {
        device: socket.handshake.headers['user-agent']?.split(' ')[0] || 'Unknown',
        ip: socket.handshake.address || 'Unknown'
      };
      await presenceService.userConnected(userId, socket.id, deviceInfo);
      
      // Send initial presence data to newly connected user
      // This ensures they see who's already online
      presenceService.sendInitialPresence(socket, userId);
      
      // Catchup delivered receipts (Backend1 style)
      await presenceService.catchupDelivered(userId);
    }

    // ============ MESSAGING ============

    /**
     * Send message (Backend style)
     */
    socket.on('send-message', async (data) => {
      try {
        const {
          conversationId,
          content,
          message,
          type = 'text',
          media,
          replyTo,
          clientId
        } = data;

        if (!conversationId || (!content && !message)) {
          socket.emit('error', { message: 'Conversation ID and content are required' });
          return;
        }

        const result = await messageService.sendMessage({
          senderId: userId,
          from: userId,
          conversationId,
          conversation: conversationId,
          content: content || message,
          text: content || message,
          type,
          media,
          replyTo,
          clientId
        });

        socket.emit('message-sent', {
          ...result.toObject(),
          clientId
        });
      } catch (error) {
        console.error('❌ Send message error:', error);
        socket.emit('error', { message: error.message || 'Error sending message' });
      }
    });

    /**
     * Receive message (handled by messageService.broadcastToConversation)
     * Client listens to 'receive-message' and 'message' events
     */

    /**
     * Mark messages as read
     */
    socket.on('mark-read', async (data) => {
      try {
        const { conversationId, messageIds } = data;

        if (!conversationId) {
          socket.emit('error', { message: 'Conversation ID is required' });
          return;
        }

        await messageService.markMessagesAsRead(conversationId, userId, messageIds);
        socket.emit('messages-read', { conversationId });
      } catch (error) {
        console.error('❌ Mark read error:', error);
        socket.emit('error', { message: error.message || 'Error marking messages as read' });
      }
    });

    /**
     * Delivered receipt (cursor-based, Backend1 style)
     */
    socket.on('delivered', async (data = {}) => {
      try {
        const { messageId } = data;
        if (!messageId) return;

        const Message = (await import('../models/Message.js')).default;
        const Conversation = (await import('../models/Conversation.js')).default;

        const msg = await Message.findById(messageId)
          .select('_id from sender to conversation conversationId createdAt')
          .lean();

        if (!msg) return;

        const receiverId = String(msg.to || userId);
        const senderId = String(msg.from || msg.sender);
        const convId = String(msg.conversation || msg.conversationId);
        const ts = msg.createdAt;

        // Update cursor
        await Conversation.updateOne(
          { _id: convId },
          {
            $max: { [`deliveredUpTo.${receiverId}`]: ts },
            $set: { updatedAt: new Date() }
          }
        );

        // Notify sender
        if (presenceService) {
          presenceService.sendToUser(senderId, 'delivered', {
            messageId: String(msg._id),
            conversationId: convId,
            by: receiverId,
            at: ts.toISOString()
          });
        }
      } catch (error) {
        console.error('❌ Delivered receipt error:', error);
      }
    });

    /**
     * Read up to (cursor-based, Backend1 style)
     */
    socket.on('read_up_to', async (data = {}) => {
      try {
        const { conversationId, by, at } = data;
        if (!conversationId || !by) return;

        const Conversation = (await import('../models/Conversation.js')).default;
        const ts = at ? new Date(at) : new Date();

        await Conversation.updateOne(
          { _id: conversationId },
          {
            $max: { [`readUpTo.${String(by)}`]: ts },
            $set: { updatedAt: new Date() }
          }
        );

        const conv = await Conversation.findById(conversationId)
          .select('participants members')
          .lean();

        if (!conv) return;

        const members = conv.participants || conv.members || [];
        for (const p of members) {
          const pid = String(p);
          if (pid !== String(by) && presenceService) {
            presenceService.sendToUser(pid, 'read_up_to', {
              conversationId: String(conversationId),
              by: String(by),
              at: ts.toISOString()
            });
          }
        }
      } catch (error) {
        console.error('❌ Read up to error:', error);
      }
    });

    // ============ TYPING ============

    /**
     * Typing indicator
     */
    socket.on('typing', async (data = {}) => {
      try {
        const { conversationId, to, typing = true } = data;

        // Validate conversationId before processing
        if (!conversationId || conversationId === 'null' || conversationId === 'undefined' || String(conversationId).trim() === '') {
          console.warn('⚠️ Typing event received with invalid conversationId:', conversationId);
          return;
        }

        if (presenceService) {
          if (typing) {
            presenceService.userTyping(userId, conversationId);
          } else {
            presenceService.userStoppedTyping(userId, conversationId);
          }
        } else {
          // Fallback: direct emit
          const targetUserId = to || '';
          if (targetUserId) {
            io.to(targetUserId).emit('typing', {
              from: userId,
              conversationId: conversationId || null,
              typing,
              at: new Date().toISOString()
            });
          }
        }
      } catch (error) {
        console.error('❌ Typing error:', error);
      }
    });

    /**
     * Typing stopped
     */
    socket.on('typing-stopped', async (data = {}) => {
      try {
        const { conversationId } = data;
        if (presenceService && conversationId) {
          presenceService.userStoppedTyping(userId, conversationId);
        }
      } catch (error) {
        console.error('❌ Typing stopped error:', error);
      }
    });

    // ============ CALLS (WebRTC) ============

    /**
     * Call invite (Backend1 style - call:invite)
     */
    socket.on('call:invite', async (data = {}) => {
      try {
        const { to, sdp, kind = 'audio' } = data;

        if (!to || !sdp?.type || !sdp?.sdp) {
          socket.emit('call:error', { message: 'Missing required fields' });
          return;
        }

        if (callService) {
          const result = await callService.inviteCall(userId, to, sdp, kind);
          if (!result.success) {
            socket.emit('call:busy', { to, error: result.error });
          }
        }
      } catch (error) {
        console.error('❌ Call invite error:', error);
        socket.emit('call:error', { message: error.message || 'Error inviting to call' });
      }
    });

    /**
     * Call answer (Backend1 style - call:answer)
     */
    socket.on('call:answer', async (data = {}) => {
      try {
        const { callId, accept = false, sdp } = data;

        if (!callId) {
          socket.emit('call:error', { message: 'Call ID is required' });
          return;
        }

        if (callService) {
          await callService.answerCall(callId, userId, accept, sdp);
        }
      } catch (error) {
        console.error('❌ Call answer error:', error);
        socket.emit('call:error', { message: error.message || 'Error answering call' });
      }
    });

    /**
     * Call candidate (ICE)
     */
    socket.on('call:candidate', async (data = {}) => {
      try {
        const { callId, candidate } = data;

        if (!callId || !candidate) return;

        if (callService) {
          await callService.relayCandidate(callId, userId, candidate);
        }
      } catch (error) {
        console.error('❌ Call candidate error:', error);
      }
    });

    /**
     * Call hangup
     */
    socket.on('call:hangup', async (data = {}) => {
      try {
        const { callId } = data;

        if (!callId) return;

        if (callService) {
          await callService.hangupCall(callId, userId);
        }
      } catch (error) {
        console.error('❌ Call hangup error:', error);
      }
    });

    // ============ LEGACY CALL SIGNALING (for compatibility) ============

    socket.on('call_offer', async (data = {}) => {
      try {
        const { to, sdp } = data;
        if (!to || !sdp) return;

        if (callService) {
          const result = await callService.inviteCall(userId, to, sdp, 'audio');
          if (!result.success && result.error === 'busy') {
            socket.emit('call_error', { error: 'busy' });
          }
        }
      } catch (error) {
        console.error('❌ Legacy call offer error:', error);
        socket.emit('call_error', { error: error.message || 'unknown' });
      }
    });

    socket.on('call_answer', async (data = {}) => {
      try {
        const { callId, sdp } = data;
        if (!callId || !sdp) return;

        if (callService) {
          await callService.answerCall(callId, userId, true, sdp);
        }
      } catch (error) {
        console.error('❌ Legacy call answer error:', error);
      }
    });

    socket.on('ice_candidate', async (data = {}) => {
      try {
        const { callId, candidate } = data;
        if (!callId || !candidate) return;

        if (callService) {
          await callService.relayCandidate(callId, userId, candidate);
        }
      } catch (error) {
        console.error('❌ Legacy ICE candidate error:', error);
      }
    });

    socket.on('call_end', async (data = {}) => {
      try {
        const { callId } = data;
        if (!callId) return;

        if (callService) {
          await callService.hangupCall(callId, userId);
        }
      } catch (error) {
        console.error('❌ Legacy call end error:', error);
      }
    });

    // ============ DISCONNECT ============

    socket.on('disconnect', async (reason) => {
      // Only log non-normal disconnects (transport close is normal)
      if (reason !== 'transport close' && reason !== 'client namespace disconnect') {
        console.log(`⚠️ Socket disconnected: ${socket.id} (User: ${userId}, Reason: ${reason})`);
      } else {
        // Normal disconnection - log at debug level only
        if (process.env.NODE_ENV === 'development') {
          console.log(`🔌 Socket disconnected: ${socket.id} (User: ${userId}, Reason: ${reason}) - will auto-reconnect`);
        }
      }

      // Remove from presence
      if (presenceService) {
        await presenceService.userDisconnected(socket.id);
      }

      // Cleanup calls
      if (callService) {
        callService.handleUserDisconnect(userId);
      }
    });

    // ============ UTILITY EVENTS ============

    /**
     * Join conversation room (optional - for granular room management)
     */
    socket.on('join-conversation', (data = {}) => {
      const { conversationId } = data;
      if (conversationId) {
        socket.join(`conversation:${conversationId}`);
        console.log(`👤 User ${userId} joined conversation ${conversationId}`);
      }
    });

    /**
     * Leave conversation room
     */
    socket.on('leave-conversation', (data = {}) => {
      const { conversationId } = data;
      if (conversationId) {
        socket.leave(`conversation:${conversationId}`);
        console.log(`👤 User ${userId} left conversation ${conversationId}`);
      }
    });

    // Emit connection confirmation
    socket.emit('connected', {
      userId,
      socketId: socket.id,
      timestamp: new Date().toISOString()
    });
  });

  // Store services on io for app access
  io.services = services;
  io.presenceService = presenceService;
  io.callService = callService;
  io.messageService = messageService;

  console.log('✅ Socket.IO handler initialized');
};

