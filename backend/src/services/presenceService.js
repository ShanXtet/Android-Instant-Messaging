import User from '../models/User.js';
import Conversation from '../models/Conversation.js';
import Message from '../models/Message.js';
import mongoose from 'mongoose';

/**
 * Presence Service
 * Handles online/offline status, multi-device tracking, and typing indicators
 */
class PresenceService {
  constructor(io) {
    this.io = io;
    // Database-backed state (not in-memory for scalability)
    this.onlineCounts = new Map(); // userId -> session count
    this.lastPresenceAt = new Map(); // userId -> last presence timestamp
    this.userSockets = new Map(); // userId -> Set of socketIds
    this.typingUsers = new Map(); // conversationId -> Set of typing userIds
  }

  /**
   * User connects - track session and update status
   */
  async userConnected(userId, socketId, deviceInfo = {}) {
    try {
      const uid = String(userId);
      
      // Track socket
      if (!this.userSockets.has(uid)) {
        this.userSockets.set(uid, new Set());
      }
      this.userSockets.get(uid).add(socketId);
      
      // Update session count
      const previousCount = this.onlineCounts.get(uid) || 0;
      const newCount = previousCount + 1;
      this.onlineCounts.set(uid, newCount);
      
      const now = new Date();
      this.lastPresenceAt.set(uid, now);
      
      // Only update DB and broadcast when going from offline (0) to online (1)
      if (previousCount === 0) {
        // Update user status in database
        await User.findByIdAndUpdate(userId, {
          isOnline: true,
          lastSeen: now
        });
        
        // Broadcast presence change
        this.io.emit('presence', {
          uid,
          online: true,
          at: now.toISOString()
        });
        
        this.io.emit('user-status-changed', {
          userId: uid,
          status: 'online',
          isOnline: true,
          lastSeen: now
        });
      }
      
      // Update online users list
      this.io.emit('online-users', Array.from(this.onlineCounts.keys()));
      
      return true;
    } catch (error) {
      console.error('Error in userConnected:', error);
      return false;
    }
  }

  /**
   * User disconnects - decrement session count
   */
  async userDisconnected(socketId) {
    try {
      // Find user for this socket
      let disconnectedUserId = null;
      for (const [userId, socketIds] of this.userSockets.entries()) {
        if (socketIds.has(socketId)) {
          disconnectedUserId = userId;
          socketIds.delete(socketId);
          
          // Clean up if no more sockets
          if (socketIds.size === 0) {
            this.userSockets.delete(userId);
            this.onlineCounts.delete(userId);
          }
          break;
        }
      }
      
      if (!disconnectedUserId) return false;
      
      const uid = disconnectedUserId;
      
      // Decrement session count
      const previousCount = this.onlineCounts.get(uid) || 1;
      const newCount = Math.max(0, previousCount - 1);
      
      if (newCount > 0) {
        this.onlineCounts.set(uid, newCount);
      } else {
        // User is going offline (last session disconnected)
        this.onlineCounts.delete(uid);
        const now = new Date();
        this.lastPresenceAt.set(uid, now);
        
        // Update user status in database
        await User.findByIdAndUpdate(disconnectedUserId, {
          isOnline: false,
          lastSeen: now
        });
        
        // Broadcast offline status
        this.io.emit('presence', {
          uid,
          online: false,
          at: now.toISOString()
        });
        
        this.io.emit('user-status-changed', {
          userId: uid,
          status: 'offline',
          isOnline: false,
          lastSeen: now
        });
      }
      
      // Update online users list
      this.io.emit('online-users', Array.from(this.onlineCounts.keys()));
      
      return true;
    } catch (error) {
      console.error('Error in userDisconnected:', error);
      return false;
    }
  }

  /**
   * Get user status
   */
  getUserStatus(userId) {
    const uid = String(userId);
    const isOnline = (this.onlineCounts.get(uid) || 0) > 0;
    const lastSeen = this.lastPresenceAt.get(uid) || null;
    
    return {
      online: isOnline,
      isOnline,
      at: lastSeen ? lastSeen.toISOString() : null,
      lastSeen
    };
  }

  /**
   * Check if user is online
   */
  isUserOnline(userId) {
    return (this.onlineCounts.get(String(userId)) || 0) > 0;
  }

  /**
   * Get online users count
   */
  getOnlineCount() {
    return this.onlineCounts.size;
  }

  /**
   * Get online users list
   */
  getOnlineUsers() {
    return Array.from(this.onlineCounts.keys());
  }

  /**
   * Get all current online statuses
   * Returns a map of userId -> { online: boolean, lastSeen: Date }
   */
  getAllOnlineStatuses() {
    const statusMap = {};
    for (const [userId, count] of this.onlineCounts.entries()) {
      statusMap[userId] = {
        online: count > 0,
        isOnline: count > 0,
        at: this.lastPresenceAt.get(userId)?.toISOString() || null,
        lastSeen: this.lastPresenceAt.get(userId)?.toISOString() || null
      };
    }
    return statusMap;
  }

  /**
   * Send initial presence data to newly connected user
   * This ensures they get current online status of all users
   */
  async sendInitialPresence(socket, userId) {
    try {
      // Get all online users from in-memory cache
      const statusMap = this.getAllOnlineStatuses();
      
      // Also get status from database for users not in cache (for completeness)
      const User = (await import('../models/User.js')).default;
      const allUsers = await User.find({})
        .select('_id isOnline lastSeen')
        .lean();
      
      // Merge database status with in-memory status (in-memory takes precedence)
      // IMPORTANT: Users in onlineCounts (currently connected) are ALWAYS online
      for (const user of allUsers) {
        const uid = String(user._id);
        if (!statusMap[uid]) {
          // User not in cache, use database status
          statusMap[uid] = {
            online: user.isOnline || false,
            isOnline: user.isOnline || false,
            at: user.lastSeen ? user.lastSeen.toISOString() : null,
            lastSeen: user.lastSeen ? user.lastSeen.toISOString() : null
          };
        } else {
          // User in cache - ensure they're marked as online if they have active connections
          // This ensures real-time status takes precedence over potentially stale DB data
          const isCurrentlyOnline = (this.onlineCounts.get(uid) || 0) > 0;
          if (isCurrentlyOnline) {
            statusMap[uid].online = true;
            statusMap[uid].isOnline = true;
          }
          // Ensure database lastSeen is included if cache doesn't have it
          if (!statusMap[uid].lastSeen && user.lastSeen) {
            statusMap[uid].lastSeen = user.lastSeen.toISOString();
            statusMap[uid].at = user.lastSeen.toISOString();
          }
        }
      }
      
      socket.emit('presence:initial', {
        users: statusMap,
        timestamp: new Date().toISOString()
      });
      console.log(`📡 Sent initial presence to ${userId}: ${Object.keys(statusMap).length} users (${this.onlineCounts.size} online)`);
    } catch (error) {
      console.error('Error sending initial presence:', error);
    }
  }

  /**
   * User starts typing
   */
  userTyping(userId, conversationId) {
    // Validate conversationId before processing
    if (!conversationId || conversationId === 'null' || conversationId === 'undefined' || String(conversationId).trim() === '') {
      console.warn('⚠️ userTyping called with invalid conversationId:', conversationId);
      return;
    }

    const uid = String(userId);
    const cid = String(conversationId).trim();
    
    // Validate ObjectId format
    if (cid.length !== 24 || !/^[a-f0-9]{24}$/i.test(cid)) {
      console.warn('⚠️ userTyping called with invalid ObjectId format:', conversationId);
      return;
    }
    
    if (!this.typingUsers.has(cid)) {
      this.typingUsers.set(cid, new Set());
    }
    this.typingUsers.get(cid).add(uid);
    
    // Broadcast typing to conversation members
    this.broadcastToConversation(cid, 'typing', {
      from: uid,
      conversationId: cid,
      typing: true,
      at: new Date().toISOString()
    }, uid);
  }

  /**
   * User stops typing
   */
  userStoppedTyping(userId, conversationId) {
    // Validate conversationId before processing
    if (!conversationId || conversationId === 'null' || conversationId === 'undefined' || String(conversationId).trim() === '') {
      console.warn('⚠️ userStoppedTyping called with invalid conversationId:', conversationId);
      return;
    }

    const uid = String(userId);
    const cid = String(conversationId).trim();
    
    // Validate ObjectId format
    if (cid.length !== 24 || !/^[a-f0-9]{24}$/i.test(cid)) {
      console.warn('⚠️ userStoppedTyping called with invalid ObjectId format:', conversationId);
      return;
    }
    
    if (this.typingUsers.has(cid)) {
      this.typingUsers.get(cid).delete(uid);
      
      // Broadcast typing stopped
      this.broadcastToConversation(cid, 'typing-stopped', {
        from: uid,
        conversationId: cid,
        typing: false,
        at: new Date().toISOString()
      }, uid);
    }
  }

  /**
   * Get typing users for a conversation
   */
  getTypingUsers(conversationId) {
    const cid = String(conversationId);
    return this.typingUsers.has(cid) 
      ? Array.from(this.typingUsers.get(cid))
      : [];
  }

  /**
   * Broadcast to all users in a conversation
   */
  async broadcastToConversation(conversationId, event, data, excludeUserId = null) {
    try {
      // Validate conversationId - must be a valid string/ObjectId, not null/undefined
      if (!conversationId || conversationId === 'null' || conversationId === 'undefined' || String(conversationId).trim() === '') {
        console.warn('⚠️ broadcastToConversation called with invalid conversationId:', conversationId);
        return;
      }

      // Convert to string and validate it looks like a MongoDB ObjectId
      const convIdStr = String(conversationId).trim();
      if (convIdStr.length !== 24 || !/^[a-f0-9]{24}$/i.test(convIdStr)) {
        console.warn('⚠️ broadcastToConversation called with invalid ObjectId format:', conversationId);
        return;
      }

      const conversation = await Conversation.findById(convIdStr).lean();
      if (!conversation) {
        console.warn('⚠️ Conversation not found for ID:', convIdStr);
        return;
      }
      
      const members = conversation.participants || conversation.members || [];
      const exclude = excludeUserId ? String(excludeUserId) : null;
      
      members.forEach(memberId => {
        const memberUid = String(memberId);
        if (exclude && memberUid === exclude) return;
        
        const sockets = this.userSockets.get(memberUid);
        if (sockets) {
          sockets.forEach(socketId => {
            this.io.to(socketId).emit(event, data);
          });
        }
      });
    } catch (error) {
      console.error('Error broadcasting to conversation:', error);
    }
  }

  /**
   * Send to specific user (all their sockets)
   */
  sendToUser(userId, event, data) {
    const uid = String(userId);
    const sockets = this.userSockets.get(uid);
    if (sockets) {
      sockets.forEach(socketId => {
        this.io.to(socketId).emit(event, data);
      });
    }
  }

  /**
   * Send to multiple users
   */
  sendToUsers(userIds, event, data) {
    userIds.forEach(userId => {
      this.sendToUser(userId, event, data);
    });
  }

  /**
   * Broadcast to all users
   */
  broadcastToAll(event, data) {
    this.io.emit(event, data);
  }

  /**
   * Catchup delivered receipts on user connect (Backend1 style)
   */
  async catchupDelivered(userId) {
    try {
      const uid = String(userId);
      const U = new mongoose.Types.ObjectId(userId);

      // Find messages sent to this user, grouped by conversation
      const groups = await Message.aggregate([
        { 
          $match: { 
            $or: [
              { to: U },
              { sender: { $ne: U } } // Messages not sent by this user
            ],
            deleted: { $ne: true },
            isDeleted: { $ne: true }
          } 
        },
        { $sort: { createdAt: -1 } },
        { 
          $group: {
            _id: '$conversation',
            lastId: { $first: '$_id' },
            lastAt: { $first: '$createdAt' },
            from: { $first: '$from' }
          }
        }
      ]);

      if (!groups.length) return;

      const convIds = groups.map(g => g._id).filter(Boolean);
      const convs = await Conversation
        .find({ _id: { $in: convIds } })
        .select('deliveredUpTo')
        .lean();

      const deliveredMap = {};
      for (const c of convs) {
        const v = (c.deliveredUpTo || {})[uid];
        deliveredMap[String(c._id)] = v ? new Date(v) : null;
      }

      // Update delivered cursors and notify senders
      for (const g of groups) {
        if (!g || !g._id || !g.lastAt) continue;
        const cid = String(g._id);
        const prev = deliveredMap[cid];
        const lastAt = new Date(g.lastAt);
        
        if (!prev || lastAt > prev) {
          // Update cursor in database
          await Conversation.updateOne(
            { _id: g._id },
            { 
              $max: { [`deliveredUpTo.${uid}`]: lastAt }, 
              $set: { updatedAt: new Date() } 
            }
          );
          
          // Notify sender
          if (g.from) {
            const senderId = String(g.from);
            this.sendToUser(senderId, 'delivered', {
              messageId: String(g.lastId),
              conversationId: cid,
              by: uid,
              at: lastAt.toISOString()
            });
          }
        }
      }
    } catch (error) {
      console.error('catchupDelivered error:', error);
    }
  }
}

export default PresenceService;

