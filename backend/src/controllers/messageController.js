import Conversation from '../models/Conversation.js';
import Message from '../models/Message.js';
import User from '../models/User.js';
import { normalizePhone } from '../utils/phoneNormalizer.js';
import config from '../config/index.js';
import mongoose from 'mongoose';

/**
 * Helper: Get user ID by phone
 */
const uidByPhone = async (phone) => {
  const normalized = normalizePhone(phone);
  const u = await User.findOne({ phone: normalized }).select('_id').lean();
  return u?._id ? String(u._id) : null;
};

/**
 * Helper: Pair users for conversation lookup
 */
const pair = (a, b) => {
  const A = String(a), B = String(b);
  return A < B ? [A, B] : [B, A];
};

/**
 * Send a new message
 * Supports both Backend and Backend1 formats
 */
export const sendMessage = async (req, res) => {
  const messageService = req.app.get('messageService');
  if (!messageService || typeof messageService.sendMessage !== 'function') {
    console.error('❌ messageService missing or invalid on app');
    return res.status(500).json({
      success: false,
      error: 'server_error',
      message: 'Message service unavailable'
    });
  }
  try {
    const {
      from,
      senderId,
      to,
      toId,
      toPhone,
      conversationId,
      conversation,
      content,
      text,
      type = 'text',
      media,
      fileUrl,
      fileName,
      fileType,
      audioDuration: audioDurationStr,
      messageType,
      callActivity,
      callType,
      callStatus,
      isVideoCall,
      callStartTime,
      callDuration,
      replyTo,
      replyToMessage,
      clientId
    } = req.body;

    const userId = req.user.id || req.user.uid || req.user.userId;
    const sender = senderId || from || userId;

    // Validate sender
    if (String(sender) !== String(userId)) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Sender ID does not match authenticated user'
      });
    }

    const normalizedContent = (content || text || '').toString().trim();
    const audioDuration = audioDurationStr ? parseInt(audioDurationStr, 10) : null;

    // Validate content (allow empty for voice/call activity)
    const isVoice = fileType === 'audio' || fileType === 'voice' ||
                    (fileName && (fileName.endsWith('.m4a') || fileName.endsWith('.mp3') || fileName.startsWith('voice_')));
    
    if (!normalizedContent && !fileUrl && !media && !callActivity) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Message content, file, or call activity is required'
      });
    }

    if (normalizedContent.length > config.maxMessageLength) {
      return res.status(413).json({
        success: false,
        error: 'too_long',
        message: `Message exceeds maximum length of ${config.maxMessageLength} characters`
      });
    }

    let targetConversationId = conversationId || conversation;
    let targetToId = toId || to;

    // If conversationId is provided, use it directly
    if (targetConversationId) {
      // Validate ObjectId format early to avoid CastError → 500
      const validConvId = mongoose.Types.ObjectId.isValid(targetConversationId);
      if (!validConvId) {
        return res.status(400).json({
          success: false,
          error: 'invalid_conversation_id',
          message: 'Conversation ID is not valid'
        });
      }
      // Validate conversation exists
      const conv = await Conversation.findById(targetConversationId);
      if (!conv) {
        return res.status(404).json({
          success: false,
          error: 'conversation_not_found',
          message: 'Conversation not found'
        });
      }
    }
    // If no conversationId but toId/to provided, find or create conversation
    else if (targetToId) {
      // Use the provided toId directly (most reliable)
      console.log(`🔍 Using provided toId: ${targetToId}`);
      // Validate user exists
      const targetUser = await User.findById(targetToId).select('_id').lean();
      if (!targetUser) {
        return res.status(404).json({
          success: false,
          error: 'user_not_found',
          message: 'Recipient user not found'
        });
      }
    }
    // If no conversationId or toId, try toPhone as fallback
    else if (toPhone) {
      const normalizedPhone = normalizePhone(toPhone);
      console.log(`🔍 Looking up user by phone: "${toPhone}" -> normalized: "${normalizedPhone}"`);
      targetToId = await uidByPhone(toPhone);
      if (!targetToId) {
        // Check if user exists with different phone format variations
        const alternativeFormats = [
          normalizedPhone,
          normalizedPhone.replace(/^\+/, ''), // without +
          `+${normalizedPhone.replace(/^\+/, '')}`, // with +
        ];
        const existingUser = await User.findOne({
          $or: alternativeFormats.map(p => ({ phone: p }))
        }).select('_id phone').lean();
        
        if (existingUser) {
          console.log(`✅ Found user with alternative phone format: ${existingUser.phone}`);
          targetToId = String(existingUser._id);
        } else {
          console.log(`❌ No user found for phone: ${toPhone} (normalized: ${normalizedPhone})`);
          return res.status(404).json({
            success: false,
            error: 'user_not_found',
            message: `No user found for phone number. The recipient may need to register first.`,
            details: {
              phone: toPhone,
              normalized: normalizedPhone,
              suggestion: 'Make sure the recipient has registered in the app with this phone number.'
            }
          });
        }
      }
    }

    // If no conversationId but we have targetToId, find or create conversation
    if (!targetConversationId && targetToId) {
      try {
        const [A, B] = pair(sender, targetToId);
        console.log(`🔍 Looking for conversation between ${A} and ${B}`);
        let conv = await Conversation.findOne({
          $or: [
            { participants: { $all: [A, B], $size: 2 } },
            { members: { $all: [A, B], $size: 2 } }
          ],
          isGroup: false,
          status: { $in: ['active', 'pending'] }
        });

        if (!conv) {
          console.log(`📝 Creating new conversation between ${A} and ${B}`);
          conv = await Conversation.create({
            participants: [A, B],
            members: [A, B],
            isGroup: false,
            status: 'active'
          });
          console.log(`✅ Created new conversation: ${conv._id} between ${A} and ${B}`);
        } else {
          console.log(`✅ Found existing conversation: ${conv._id} between ${A} and ${B}`);
        }
        targetConversationId = String(conv._id); // Ensure it's a string
        console.log(`✅ Using conversationId: ${targetConversationId}`);
      } catch (convError) {
        console.error('❌ Error finding/creating conversation:', convError);
        throw new Error(`Failed to find or create conversation: ${convError.message}`);
      }
    }

    if (!targetConversationId) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Conversation ID or recipient (toId/toPhone) is required'
      });
    }

    // Prepare message text
    let messageText = normalizedContent;
    if (!messageText && fileUrl && !isVoice) {
      messageText = `📎 ${fileName || 'File'}`;
    } else if (!messageText && callActivity) {
      messageText = '📞 Call';
    } else if (!messageText && isVoice) {
      messageText = 'Voice Message';
    }

    // Ensure conversationId is a string
    const finalConversationId = String(targetConversationId);
    console.log(`📤 Sending message to conversation: ${finalConversationId}, sender: ${sender}, to: ${targetToId || 'N/A'}`);

    // Use message service to send
    const newMessage = await messageService.sendMessage({
      senderId: sender,
      from: sender,
      toId: targetToId,
      to: targetToId,
      conversationId: finalConversationId,
      conversation: finalConversationId,
      content: messageText,
      text: messageText,
      type,
      media,
      fileUrl,
      fileName,
      fileType,
      audioDuration,
      callActivity,
      callType,
      callStatus,
      isVideoCall,
      callStartTime,
      callDuration,
      replyTo,
      replyToMessage,
      clientId
    });

    // Build response payload
    const payload = {
      _id: String(newMessage._id),
      messageId: String(newMessage._id),
      conversationId: String(targetConversationId),
      conversation: String(targetConversationId),
      from: String(newMessage.from || newMessage.sender),
      sender: String(newMessage.sender || newMessage.from),
      to: newMessage.to ? String(newMessage.to) : undefined,
      text: newMessage.text || newMessage.content,
      content: newMessage.content || newMessage.text,
      type: newMessage.type,
      deleted: false,
      isDeleted: false,
      createdAt: newMessage.createdAt.toISOString()
    };

    if (newMessage.fileUrl || newMessage.media) {
      payload.fileUrl = newMessage.fileUrl || newMessage.media;
      payload.media = newMessage.media || newMessage.fileUrl;
      payload.fileName = newMessage.fileName;
      payload.fileType = newMessage.fileType;
      if (newMessage.audioDuration != null) {
        payload.audioDuration = newMessage.audioDuration;
      }
    }

    if (newMessage.callActivity) {
      payload.messageType = 'call_activity';
      payload.callActivity = true;
      if (newMessage.callType) payload.callType = newMessage.callType;
      if (newMessage.callStatus) payload.callStatus = newMessage.callStatus;
      if (newMessage.isVideoCall !== undefined) payload.isVideoCall = newMessage.isVideoCall;
      if (newMessage.callStartTime) payload.callStartTime = newMessage.callStartTime.toISOString();
      if (newMessage.callDuration !== undefined) payload.callDuration = newMessage.callDuration.toString();
    }

    if (newMessage.replyTo) {
      payload.replyTo = String(newMessage.replyTo);
    }
    if (newMessage.replyToMessage) {
      payload.replyToMessage = newMessage.replyToMessage;
    }

    res.status(200).json({
      success: true,
      ok: true,
      message: payload,
      data: payload // Also include as 'data' for compatibility
    });
  } catch (error) {
    console.error('❌ Send message error:', error);
    console.error('❌ Error stack:', error.stack);
    console.error('❌ Request body:', JSON.stringify(req.body, null, 2));
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error sending message',
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
};

/**
 * Get messages for a conversation
 * Supports both Backend and Backend1 query styles
 */
export const getMessages = async (req, res) => {
  try {
    const { conversationId, conversation, userA, userB } = req.params;
    const { page = 1, limit = 50, before } = req.query;
    const userId = req.user.id || req.user.uid || req.user.userId;

    let targetConversationId = conversationId || conversation;

    // Support Backend1 style: query by userA and userB
    if (!targetConversationId && userA && userB) {
      const [A, B] = pair(userA, userB);
      if (![A, B].includes(String(userId))) {
        return res.status(403).json({
          success: false,
          error: 'forbidden',
          message: 'Access denied'
        });
      }

      const conv = await Conversation.findOne({
        $or: [
          { participants: { $all: [A, B], $size: 2 } },
          { members: { $all: [A, B], $size: 2 } }
        ],
        isGroup: false
      });

      if (conv) {
        targetConversationId = conv._id;
      } else {
        // Return empty messages for non-existent conversation
        return res.json({
          success: true,
          messages: [],
          pagination: {
            totalPages: 0,
            currentPage: parseInt(page),
            total: 0,
            limit: parseInt(limit)
          }
        });
      }
    }

    if (!targetConversationId) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Conversation ID or user IDs are required'
      });
    }

    const result = await messageService.getMessages(targetConversationId, userId, {
      page: parseInt(page),
      limit: parseInt(limit),
      before
    });

    res.json({
      success: true,
      messages: result.messages,
      pagination: result.pagination
    });
  } catch (error) {
    console.error('❌ Get messages error:', error);
    
    if (error.message === 'Conversation not found') {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: error.message
      });
    }
    
    if (error.message.includes('not a member')) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: error.message
      });
    }

    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching messages'
    });
  }
};

/**
 * Edit message
 */
export const editMessage = async (req, res) => {
  try {
    const { id } = req.params;
    const { text, content } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    const newContent = (text || content || '').toString().trim();
    if (!newContent) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Message content is required'
      });
    }

    if (newContent.length > config.maxMessageLength) {
      return res.status(413).json({
        success: false,
        error: 'too_long',
        message: `Message exceeds maximum length of ${config.maxMessageLength} characters`
      });
    }

    const message = await messageService.editMessage(id, userId, newContent);

    const payload = {
      _id: String(message._id),
      messageId: String(message._id),
      conversationId: message.conversation ? String(message.conversation) : String(message.conversationId),
      conversation: message.conversation ? String(message.conversation) : String(message.conversationId),
      from: String(message.from || message.sender),
      sender: String(message.sender || message.from),
      to: message.to ? String(message.to) : undefined,
      text: newContent,
      content: newContent,
      edited: true,
      editedAt: message.editedAt.toISOString(),
      createdAt: message.createdAt.toISOString()
    };

    res.json({
      success: true,
      ok: true,
      message: payload
    });
  } catch (error) {
    console.error('❌ Edit message error:', error);
    
    if (error.message === 'Message not found') {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: error.message
      });
    }
    
    if (error.message.includes('Only sender')) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: error.message
      });
    }

    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error editing message'
    });
  }
};

/**
 * Delete message
 */
export const deleteMessage = async (req, res) => {
  try {
    const { id } = req.params;
    const { deleteForBoth } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    await messageService.deleteMessage(id, userId, deleteForBoth === true);

    const message = await Message.findById(id).lean();
    
    const payload = {
      _id: String(message._id),
      messageId: String(message._id),
      conversationId: message.conversation ? String(message.conversation) : String(message.conversationId),
      conversation: message.conversation ? String(message.conversation) : String(message.conversationId),
      from: String(message.from || message.sender),
      deleted: true,
      isDeleted: true,
      deletedAt: message.deletedAt?.toISOString()
    };

    res.json({
      success: true,
      ok: true,
      message: payload
    });
  } catch (error) {
    console.error('❌ Delete message error:', error);
    
    if (error.message === 'Message not found') {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: error.message
      });
    }

    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error deleting message'
    });
  }
};

/**
 * Mark message as read
 */
export const markAsRead = async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.id || req.user.uid || req.user.userId;

    const message = await Message.findById(id);
    if (!message) {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: 'Message not found'
      });
    }

    await Message.findByIdAndUpdate(id, {
      status: 'read',
      readAt: new Date(),
      $addToSet: { readBy: userId }
    });

    res.json({
      success: true,
      message: 'Message marked as read'
    });
  } catch (error) {
    console.error('❌ Mark as read error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error marking message as read'
    });
  }
};

/**
 * Search messages
 */
export const searchMessages = async (req, res) => {
  try {
    const { query } = req.query;
    const userId = req.user.id || req.user.uid || req.user.userId;

    if (!query || query.trim().length < 2) {
      return res.json({
        success: true,
        messages: []
      });
    }

    // Get user's conversations
    const userConversations = await Conversation.find({
      $or: [
        { participants: userId },
        { members: userId }
      ]
    }).select('_id').lean();

    const conversationIds = userConversations.map(conv => conv._id);

    // Search messages
    const messages = await Message.find({
      $or: [
        { conversation: { $in: conversationIds } },
        { conversationId: { $in: conversationIds } }
      ],
      $or: [
        { content: { $regex: query, $options: 'i' } },
        { text: { $regex: query, $options: 'i' } }
      ],
      deleted: { $ne: true },
      isDeleted: { $ne: true },
      deletedFor: { $nin: [userId] }
    })
      .populate('sender', 'name phone avatar avatarUrl')
      .populate('from', 'name phone avatar avatarUrl')
      .sort({ createdAt: -1 })
      .limit(20)
      .lean();

    const formatted = messages.map(m => ({
      _id: String(m._id),
      from: String(m.from || m.sender),
      sender: String(m.sender || m.from),
      text: m.text || m.content,
      content: m.content || m.text,
      conversation: m.conversation ? String(m.conversation) : String(m.conversationId),
      conversationId: m.conversationId ? String(m.conversationId) : String(m.conversation),
      createdAt: m.createdAt?.toISOString()
    }));

    res.json({
      success: true,
      messages: formatted
    });
  } catch (error) {
    console.error('❌ Search messages error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error searching messages'
    });
  }
};

/**
 * Upload voice message
 */
export const uploadVoiceMessage = async (req, res) => {
  try {
    const { conversationId } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    if (!conversationId) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Conversation ID is required'
      });
    }

    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Voice file is required'
      });
    }

    // Verify conversation and membership
    const conversation = await Conversation.findById(conversationId);
    if (!conversation) {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: 'Conversation not found'
      });
    }

    const members = conversation.participants || conversation.members || [];
    const isMember = members.some(m => String(m) === String(userId));
    if (!isMember) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Not a member of this conversation'
      });
    }

    // Build file URL
    const protocol = req.protocol || 'http';
    const host = req.get('host') || 'localhost:3000';
    const fileUrl = `${protocol}://${host}/uploads/voices/${req.file.filename}`;

    // Create message with voice data
    const newMessage = await messageService.sendMessage({
      senderId: userId,
      from: userId,
      conversationId,
      conversation: conversationId,
      content: 'Voice Message',
      text: 'Voice Message',
      type: 'voice',
      fileUrl,
      fileName: req.file.filename,
      fileType: 'audio',
      audioDuration: req.body.audioDuration ? parseInt(req.body.audioDuration, 10) : null
    });

    res.status(201).json({
      success: true,
      message: {
        _id: String(newMessage._id),
        conversationId: String(conversationId),
        from: String(userId),
        type: 'voice',
        fileUrl,
        fileName: req.file.filename,
        fileType: 'audio',
        createdAt: newMessage.createdAt.toISOString()
      }
    });
  } catch (error) {
    console.error('❌ Upload voice message error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error uploading voice message'
    });
  }
};

// Export default object for route compatibility
export default {
  sendMessage,
  getMessages,
  editMessage,
  deleteMessage,
  markAsRead,
  searchMessages,
  uploadVoiceMessage
};

