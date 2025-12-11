import Message from '../models/Message.js';
import Conversation from '../models/Conversation.js';
import User from '../models/User.js';
import mongoose from 'mongoose';

/**
 * Message Service
 * Handles all message-related business logic
 * Supports both Backend and Backend1 field naming conventions
 */
class MessageService {
  constructor(io, presenceService, notificationService) {
    this.io = io;
    this.presenceService = presenceService;
    this.notificationService = notificationService;
  }

  /**
   * Send a new message
   * Supports both from/to (Backend1) and sender (Backend) formats
   */
  async sendMessage(messageData) {
    try {
      const {
        senderId,
        from,
        toId,
        to,
        conversationId,
        conversation,
        content,
        text,
        type = 'text',
        media,
        fileUrl,
        fileName,
        fileType,
        audioDuration,
        replyTo,
        replyToMessage,
        callActivity,
        callType,
        callStatus,
        isVideoCall,
        callStartTime,
        callDuration
      } = messageData;

      // Normalize field names
      const normalizedSenderId = senderId || from;
      const normalizedToId = toId || to;
      const normalizedConversationId = conversationId || conversation;
      const normalizedContent = content || text;

      // Validate conversationId is not null/undefined/empty
      if (!normalizedConversationId || 
          normalizedConversationId === 'null' || 
          normalizedConversationId === 'undefined' || 
          String(normalizedConversationId).trim() === '') {
        throw new Error('Valid conversation ID is required');
      }

      // Validate conversationId format (MongoDB ObjectId)
      const convIdStr = String(normalizedConversationId).trim();
      if (convIdStr.length !== 24 || !/^[a-f0-9]{24}$/i.test(convIdStr)) {
        throw new Error('Invalid conversation ID format');
      }

      if (!normalizedSenderId) {
        throw new Error('Sender is required');
      }

      // Verify conversation exists and user is a member
      const conv = await Conversation.findById(normalizedConversationId);
      if (!conv) {
        throw new Error('Conversation not found');
      }

      const members = conv.participants || conv.members || [];
      const isMember = members.some(m => String(m) === String(normalizedSenderId));
      if (!isMember) {
        throw new Error('User is not a member of this conversation');
      }

      // Build message data (support both field names)
      const msgData = {
        from: normalizedSenderId,
        sender: normalizedSenderId,
        to: normalizedToId || (members.find(m => String(m) !== String(normalizedSenderId))),
        conversation: normalizedConversationId,
        conversationId: normalizedConversationId,
        text: normalizedContent || ' ',
        content: normalizedContent || ' ',
        type,
        deleted: false,
        isDeleted: false,
        status: 'sent'
      };

      // Add file data (unified)
      if (fileUrl || media) {
        msgData.fileUrl = fileUrl || media;
        msgData.media = media || fileUrl;
        msgData.fileName = fileName;
        msgData.fileType = fileType || type;
        if (audioDuration != null) {
          msgData.audioDuration = audioDuration;
        }
      }

      // Add call activity metadata
      if (callActivity || type === 'call_activity') {
        msgData.messageType = 'call_activity';
        msgData.callActivity = true;
        if (callType) msgData.callType = callType;
        if (callStatus) msgData.callStatus = callStatus;
        if (isVideoCall !== undefined) msgData.isVideoCall = isVideoCall;
        if (callStartTime) {
          const startTime = new Date(callStartTime);
          if (!isNaN(startTime.getTime())) msgData.callStartTime = startTime;
        }
        if (callDuration) {
          const duration = parseInt(callDuration, 10);
          if (!isNaN(duration)) msgData.callDuration = duration;
        }
      }

      // Add reply data
      if (replyTo) {
        try {
          msgData.replyTo = new mongoose.Types.ObjectId(replyTo);
        } catch (e) {
          msgData.replyTo = replyTo;
        }
      }
      if (replyToMessage) {
        msgData.replyToMessage = replyToMessage;
      }

      // Create message
      const newMessage = await Message.create(msgData);

      // Update conversation's last message
      await Conversation.findByIdAndUpdate(normalizedConversationId, {
        lastMessage: newMessage._id,
        lastMessageAt: newMessage.createdAt,
        updatedAt: new Date()
      });

      // Populate sender and reply message
      await newMessage.populate('sender', 'name phone avatar avatarUrl');
      await newMessage.populate('from', 'name phone avatar avatarUrl');
      if (newMessage.replyTo) {
        await newMessage.populate({
          path: 'replyTo',
          select: 'content text type media sender from createdAt',
          populate: {
            path: 'sender from',
            select: 'name phone avatar avatarUrl'
          }
        });
      }

      // Build payload (support both formats)
      const payload = {
        _id: String(newMessage._id),
        messageId: String(newMessage._id),
        conversationId: String(normalizedConversationId),
        conversation: String(normalizedConversationId),
        from: String(newMessage.from || newMessage.sender),
        sender: String(newMessage.sender || newMessage.from),
        to: newMessage.to ? String(newMessage.to) : undefined,
        text: newMessage.text || newMessage.content,
        content: newMessage.content || newMessage.text,
        type: newMessage.type,
        deleted: false,
        isDeleted: false,
        createdAt: newMessage.createdAt.toISOString(),
        lastMessageAt: newMessage.createdAt.toISOString()
      };

      // Add file metadata
      if (newMessage.fileUrl || newMessage.media) {
        payload.fileUrl = newMessage.fileUrl || newMessage.media;
        payload.media = newMessage.media || newMessage.fileUrl;
        payload.fileName = newMessage.fileName;
        payload.fileType = newMessage.fileType;
        if (newMessage.audioDuration != null) {
          payload.audioDuration = newMessage.audioDuration;
        }
      }

      // Add call activity
      if (newMessage.callActivity || newMessage.messageType === 'call_activity') {
        payload.messageType = 'call_activity';
        payload.callActivity = true;
        if (newMessage.callType) payload.callType = newMessage.callType;
        if (newMessage.callStatus) payload.callStatus = newMessage.callStatus;
        if (newMessage.isVideoCall !== undefined) payload.isVideoCall = newMessage.isVideoCall;
        if (newMessage.callStartTime) payload.callStartTime = newMessage.callStartTime.toISOString();
        if (newMessage.callDuration !== undefined) payload.callDuration = newMessage.callDuration.toString();
      }

      // Add reply data
      if (newMessage.replyTo) {
        payload.replyTo = String(newMessage.replyTo);
      }
      if (newMessage.replyToMessage) {
        payload.replyToMessage = newMessage.replyToMessage;
      }

      // Broadcast to all conversation members
      await this.broadcastToConversation(normalizedConversationId, 'receive-message', payload, normalizedSenderId);
      await this.broadcastToConversation(normalizedConversationId, 'message', payload, normalizedSenderId);

      // Confirm to sender
      if (this.presenceService) {
        this.presenceService.sendToUser(normalizedSenderId, 'message-sent', {
          ...payload,
          clientId: messageData.clientId // For optimistic UI updates
        });
      }

      // Create notifications
      if (this.notificationService) {
        await this.notificationService.createMessageNotification(newMessage, conv);
      }

      // Stop typing
      if (this.presenceService) {
        this.presenceService.userStoppedTyping(normalizedSenderId, normalizedConversationId);
      }

      return newMessage;
    } catch (error) {
      console.error('Error sending message:', error);
      throw error;
    }
  }

  /**
   * Edit message
   */
  async editMessage(messageId, userId, newContent) {
    try {
      const message = await Message.findById(messageId);
      if (!message) {
        throw new Error('Message not found');
      }

      const senderId = String(message.from || message.sender);
      if (senderId !== String(userId)) {
        throw new Error('Only sender can edit message');
      }

      if (message.deleted || message.isDeleted) {
        throw new Error('Cannot edit deleted message');
      }

      // Store original content if first edit
      if (!message.originalContent) {
        message.originalContent = message.content || message.text;
      }

      // Update content (both fields)
      message.content = newContent;
      message.text = newContent;
      message.edited = true;
      message.editedAt = new Date();

      await message.save();

      // Build payload
      const payload = {
        _id: String(message._id),
        messageId: String(message._id),
        conversationId: (message.conversation || message.conversationId) ? String(message.conversation || message.conversationId) : undefined,
        conversation: (message.conversation || message.conversationId) ? String(message.conversation || message.conversationId) : undefined,
        from: String(message.from || message.sender),
        sender: String(message.sender || message.from),
        to: message.to ? String(message.to) : undefined,
        text: newContent,
        content: newContent,
        edited: true,
        editedAt: message.editedAt.toISOString(),
        createdAt: message.createdAt.toISOString()
      };

      // Broadcast edit
      const convId = message.conversation || message.conversationId;
      if (convId && convId !== 'null' && convId !== 'undefined' && String(convId).trim() !== '') {
        await this.broadcastToConversation(convId, 'message_edited', payload);
        await this.broadcastToConversation(convId, 'message-edited', payload);
      }

      return message;
    } catch (error) {
      console.error('Error editing message:', error);
      throw error;
    }
  }

  /**
   * Delete message
   */
  async deleteMessage(messageId, userId, deleteForBoth = false) {
    try {
      const message = await Message.findById(messageId);
      if (!message) {
        throw new Error('Message not found');
      }

      const senderId = String(message.from || message.sender);

      // Sender can delete for everyone
      if (deleteForBoth && senderId === String(userId)) {
        message.deleted = true;
        message.isDeleted = true;
        message.deletedAt = new Date();
        await message.save();

        // Broadcast deletion
        const convId = message.conversation || message.conversationId;
        const payload = {
          _id: String(message._id),
          messageId: String(message._id),
          conversationId: convId ? String(convId) : undefined,
          conversation: convId ? String(convId) : undefined,
          from: String(message.from || message.sender),
          deleted: true,
          isDeleted: true,
          deletedAt: message.deletedAt.toISOString()
        };

        // Only broadcast if we have a valid conversationId
        if (convId && convId !== 'null' && convId !== 'undefined' && String(convId).trim() !== '') {
          await this.broadcastToConversation(convId, 'message_deleted', payload);
          await this.broadcastToConversation(convId, 'message-deleted', payload);
        }

        // Update conversation lastMessage if needed
        if (convId) {
          await this.recomputeLastMessage(convId);
        }
      } else {
        // Delete for this user only
        if (!message.deletedFor) {
          message.deletedFor = [];
        }
        const uid = new mongoose.Types.ObjectId(userId);
        if (!message.deletedFor.includes(uid)) {
          message.deletedFor.push(uid);
          await message.save();
        }
      }

      return message;
    } catch (error) {
      console.error('Error deleting message:', error);
      throw error;
    }
  }

  /**
   * Get messages for conversation
   */
  async getMessages(conversationId, userId, options = {}) {
    const { page = 1, limit = 50, before } = options;

    // Verify user is a member
    const conversation = await Conversation.findById(conversationId);
    if (!conversation) {
      throw new Error('Conversation not found');
    }

    const members = conversation.participants || conversation.members || [];
    const isMember = members.some(m => String(m) === String(userId));
    if (!isMember) {
      throw new Error('User is not a member of this conversation');
    }

    // Build query
    const query = {
      $or: [
        { conversation: conversationId },
        { conversationId: conversationId }
      ],
      deleted: { $ne: true },
      isDeleted: { $ne: true },
      deletedFor: { $nin: [userId] }
    };

    if (before) {
      query.createdAt = { $lt: new Date(before) };
    }

    const messages = await Message.find(query)
      .populate('sender', 'name phone avatar avatarUrl')
      .populate('from', 'name phone avatar avatarUrl')
      .populate({
        path: 'replyTo',
        select: 'content text type media sender from createdAt',
        populate: {
          path: 'sender from',
          select: 'name phone avatar avatarUrl'
        }
      })
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip((parseInt(page) - 1) * parseInt(limit))
      .lean();

    const total = await Message.countDocuments(query);

    // Format messages (support both field names)
    const formatted = messages.reverse().map(m => ({
      _id: String(m._id),
      messageId: String(m._id),
      from: String(m.from || m.sender),
      sender: String(m.sender || m.from),
      to: m.to ? String(m.to) : undefined,
      text: m.deleted || m.isDeleted ? '' : (m.text || m.content || ''),
      content: m.deleted || m.isDeleted ? '' : (m.content || m.text || ''),
      conversation: m.conversation ? String(m.conversation) : String(m.conversationId),
      conversationId: m.conversationId ? String(m.conversationId) : String(m.conversation),
      deleted: !!m.deleted || !!m.isDeleted,
      isDeleted: !!m.isDeleted || !!m.deleted,
      deletedAt: m.deletedAt?.toISOString(),
      edited: m.edited || false,
      editedAt: m.editedAt?.toISOString(),
      createdAt: m.createdAt?.toISOString(),
      fileUrl: m.fileUrl || m.media,
      media: m.media || m.fileUrl,
      fileName: m.fileName,
      fileType: m.fileType,
      audioDuration: m.audioDuration,
      type: m.type,
      replyTo: m.replyTo ? String(m.replyTo) : undefined,
      replyToMessage: m.replyToMessage,
      ...(m.callActivity && {
        messageType: 'call_activity',
        callActivity: true,
        callType: m.callType,
        callStatus: m.callStatus,
        isVideoCall: m.isVideoCall,
        callStartTime: m.callStartTime?.toISOString(),
        callDuration: m.callDuration?.toString()
      })
    }));

    return {
      messages: formatted,
      pagination: {
        totalPages: Math.ceil(total / limit),
        currentPage: parseInt(page),
        total,
        limit: parseInt(limit)
      }
    };
  }

  /**
   * Recompute conversation's last message
   */
  async recomputeLastMessage(conversationId) {
    const last = await Message.findOne({
      $or: [
        { conversation: conversationId },
        { conversationId: conversationId }
      ],
      deleted: { $ne: true },
      isDeleted: { $ne: true }
    })
      .sort({ createdAt: -1 })
      .select('_id createdAt')
      .lean();

    if (last) {
      await Conversation.findByIdAndUpdate(conversationId, {
        lastMessage: last._id,
        lastMessageAt: last.createdAt,
        updatedAt: new Date()
      });
    } else {
      await Conversation.findByIdAndUpdate(conversationId, {
        $unset: { lastMessage: 1, lastMessageAt: 1 },
        updatedAt: new Date()
      });
    }
  }

  /**
   * Broadcast to conversation members
   */
  async broadcastToConversation(conversationId, event, data, excludeUserId = null) {
    if (!this.presenceService) return;

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

        this.presenceService.sendToUser(memberUid, event, data);
      });
    } catch (error) {
      console.error('Error broadcasting to conversation:', error);
    }
  }

  /**
   * Mark messages as read (cursor-based)
   */
  async markMessagesAsRead(conversationId, userId, messageIds = null) {
    try {
      const conversation = await Conversation.findById(conversationId);
      if (!conversation) {
        throw new Error('Conversation not found');
      }

      const uid = String(userId);
      const now = new Date();

      if (messageIds && messageIds.length > 0) {
        // Mark specific messages
        await Message.updateMany(
          {
            _id: { $in: messageIds },
            $or: [
              { from: { $ne: userId } },
              { sender: { $ne: userId } }
            ]
          },
          {
            $set: {
              status: 'read',
              readAt: now
            },
            $addToSet: { readBy: userId }
          }
        );
      } else {
        // Mark all unread messages in conversation
        const unreadMessages = await Message.find({
          $or: [
            { conversation: conversationId },
            { conversationId: conversationId }
          ],
          $or: [
            { from: { $ne: userId } },
            { sender: { $ne: userId } }
          ],
          status: { $ne: 'read' },
          deleted: { $ne: true },
          isDeleted: { $ne: true }
        }).select('_id createdAt').lean();

        if (unreadMessages.length > 0) {
          const latestTimestamp = unreadMessages[unreadMessages.length - 1].createdAt;
          
          await Message.updateMany(
            {
              _id: { $in: unreadMessages.map(m => m._id) }
            },
            {
              $set: {
                status: 'read',
                readAt: now
              },
              $addToSet: { readBy: userId }
            }
          );

          // Update cursor
          await Conversation.updateOne(
            { _id: conversationId },
            {
              $max: { [`readUpTo.${uid}`]: latestTimestamp },
              $set: { updatedAt: now }
            }
          );

          // Notify senders
          const messageDocs = await Message.find({
            _id: { $in: unreadMessages.map(m => m._id) }
          }).select('from sender').lean();

          const uniqueSenderIds = [...new Set(
            messageDocs.map(m => String(m.from || m.sender)).filter(id => id !== uid)
          )];

          uniqueSenderIds.forEach(senderId => {
            if (this.presenceService) {
              this.presenceService.sendToUser(senderId, 'messages:read-receipt', {
                conversationId: String(conversationId),
                messageIds: unreadMessages.map(m => String(m._id)),
                readBy: uid,
                readAt: now.toISOString()
              });
            }
          });
        }
      }

      return true;
    } catch (error) {
      console.error('Error marking messages as read:', error);
      throw error;
    }
  }
}

export default MessageService;

