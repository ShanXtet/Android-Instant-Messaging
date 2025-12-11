import Conversation from '../models/Conversation.js';
import Message from '../models/Message.js';
import User from '../models/User.js';
import { normalizePhone } from '../utils/phoneNormalizer.js';
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
 * Get user's conversations with cursor receipts and previews
 */
export const getConversations = async (req, res) => {
  try {
    const { me, status = 'active' } = req.query;
    const userId = req.user.id || req.user.uid || req.user.userId;
    const targetUserId = me || userId;

    if (String(targetUserId) !== String(userId)) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Access denied'
      });
    }

    // Find conversations (support both participants and members)
    const conversations = await Conversation.find({
      $or: [
        { participants: targetUserId },
        { members: targetUserId }
      ],
      hiddenFor: { $nin: [targetUserId] },
      status
    })
      .populate('participants', 'name phone isOnline lastSeen avatar avatarUrl')
      .populate('members', 'name phone isOnline lastSeen avatar avatarUrl')
      .populate({
        path: 'lastMessage',
        populate: {
          path: 'sender from',
          select: 'name phone avatar avatarUrl'
        }
      })
      .sort({ lastMessageAt: -1, updatedAt: -1 })
      .lean();

    const convIds = conversations.map(c => c._id);

    // Get last outgoing message timestamps (Backend1 style)
    const outLast = await Message.aggregate([
      {
        $match: {
          $or: [
            { conversation: { $in: convIds } },
            { conversationId: { $in: convIds } }
          ],
          $or: [
            { from: new mongoose.Types.ObjectId(targetUserId) },
            { sender: new mongoose.Types.ObjectId(targetUserId) }
          ],
          deleted: { $ne: true },
          isDeleted: { $ne: true }
        }
      },
      {
        $group: {
          _id: '$conversation',
          lastOutgoingAt: { $max: '$createdAt' }
        }
      }
    ]);
    const outMap = {};
    for (const r of outLast) {
      const id = String(r._id || r.conversationId);
      outMap[id] = r.lastOutgoingAt;
    }

    // Get message previews (last message per conversation)
    const previews = await Message.aggregate([
      {
        $match: {
          $or: [
            { conversation: { $in: convIds } },
            { conversationId: { $in: convIds } }
          ],
          deleted: { $ne: true },
          isDeleted: { $ne: true }
        }
      },
      { $sort: { createdAt: -1 } },
      {
        $group: {
          _id: '$conversation',
          text: { $first: '$text' },
          content: { $first: '$content' },
          from: { $first: '$from' },
          sender: { $first: '$sender' },
          at: { $first: '$createdAt' }
        }
      }
    ]);

    const prevTextMap = {};
    const prevFromMap = {};
    for (const p of previews) {
      const k = String(p._id);
      prevTextMap[k] = p.text || p.content || '';
      prevFromMap[k] = p.from ? String(p.from) : (p.sender ? String(p.sender) : '');
    }

    // Get unread counts
    const unreadCounts = await Message.aggregate([
      {
        $match: {
          $or: [
            { conversation: { $in: convIds } },
            { conversationId: { $in: convIds } }
          ],
          $or: [
            { from: { $ne: new mongoose.Types.ObjectId(targetUserId) } },
            { sender: { $ne: new mongoose.Types.ObjectId(targetUserId) } }
          ],
          status: { $ne: 'read' },
          deleted: { $ne: true },
          isDeleted: { $ne: true }
        }
      },
      {
        $group: {
          _id: '$conversation',
          count: { $sum: 1 }
        }
      }
    ]);

    const unreadMap = {};
    for (const u of unreadCounts) {
      unreadMap[String(u._id)] = u.count;
    }

    // Format response
    const formatted = conversations.map(c => ({
      ...c,
      _id: String(c._id),
      participants: (c.participants || c.members || []).map(p => ({
        _id: String(p._id || p),
        id: String(p._id || p),
        name: p.name,
        phone: p.phone,
        avatar: p.avatar || p.avatarUrl,
        avatarUrl: p.avatarUrl || p.avatar,
        isOnline: p.isOnline,
        lastSeen: p.lastSeen
      })),
      members: (c.members || c.participants || []).map(m => ({
        _id: String(m._id || m),
        id: String(m._id || m),
        name: m.name,
        phone: m.phone,
        avatar: m.avatar || m.avatarUrl,
        avatarUrl: m.avatarUrl || m.avatar,
        isOnline: m.isOnline,
        lastSeen: m.lastSeen
      })),
      lastPreview: prevTextMap[String(c._id)] || '',
      lastFrom: prevFromMap[String(c._id)] || '',
      lastOutgoingAt: outMap[String(c._id)] || null,
      deliveredUpTo: c.deliveredUpTo || {},
      readUpTo: c.readUpTo || {},
      unreadCount: unreadMap[String(c._id)] || 0
    }));

    res.json({
      success: true,
      conversations: formatted
    });
  } catch (error) {
    console.error('❌ Get conversations error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching conversations'
    });
  }
};

/**
 * Create a new conversation
 */
export const createConversation = async (req, res) => {
  try {
    const { participants, members, type = 'direct', otherUserId } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    // Support both participants and otherUserId
    let allParticipants = participants || members || [];
    if (otherUserId && !allParticipants.length) {
      allParticipants = [otherUserId];
    }

    // Add current user if not included
    if (!allParticipants.includes(userId)) {
      allParticipants = [...allParticipants, userId];
    }

    // Remove duplicates
    allParticipants = [...new Set(allParticipants.map(String))];

    // Check if conversation already exists (for direct messages)
    if (type === 'direct' || !type || allParticipants.length === 2) {
      const [A, B] = pair(allParticipants[0], allParticipants[1]);
      let existing = await Conversation.findOne({
        $or: [
          { participants: { $all: [A, B], $size: 2 } },
          { members: { $all: [A, B], $size: 2 } }
        ],
        isGroup: false
      });

      // Also check by participantKey if exists
      if (!existing) {
        const participantKey = [A, B].sort().join(':');
        existing = await Conversation.findOne({
          participantKey,
          isGroup: false
        });
      }

      if (existing) {
        // Unhide if was hidden
        if (existing.hiddenFor && existing.hiddenFor.includes(userId)) {
          await Conversation.findByIdAndUpdate(existing._id, {
            $pull: { hiddenFor: userId }
          });
        }

        await existing.populate([
          { path: 'participants', select: 'name phone isOnline lastSeen avatar avatarUrl' },
          { path: 'members', select: 'name phone isOnline lastSeen avatar avatarUrl' }
        ]);

        return res.json({
          success: true,
          conversation: existing
        });
      }
    }

    // Create new conversation
    const conversation = await Conversation.create({
      participants: allParticipants,
      members: allParticipants,
      isGroup: type === 'group',
      status: 'active',
      createdBy: userId
    });

    await conversation.populate([
      { path: 'participants', select: 'name phone isOnline lastSeen avatar avatarUrl' },
      { path: 'members', select: 'name phone isOnline lastSeen avatar avatarUrl' }
    ]);

    res.status(201).json({
      success: true,
      conversation
    });
  } catch (error) {
    console.error('❌ Create conversation error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error creating conversation'
    });
  }
};

/**
 * Get conversation details
 */
export const getConversationDetails = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const userId = req.user.id || req.user.uid || req.user.userId;

    const conversation = await Conversation.findById(conversationId)
      .populate('participants', 'name phone isOnline lastSeen avatar avatarUrl')
      .populate('members', 'name phone isOnline lastSeen avatar avatarUrl')
      .populate('lastMessage');

    if (!conversation) {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: 'Conversation not found'
      });
    }

    const members = conversation.participants || conversation.members || [];
    const isMember = members.some(m => String(m._id || m) === String(userId));
    if (!isMember) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Not a member of this conversation'
      });
    }

    res.json({
      success: true,
      conversation
    });
  } catch (error) {
    console.error('❌ Get conversation details error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching conversation details'
    });
  }
};

/**
 * Delete/Hide conversation
 */
export const deleteConversation = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const userId = req.user.id || req.user.uid || req.user.userId;

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

    // Hide conversation for this user
    await Conversation.findByIdAndUpdate(conversationId, {
      $addToSet: { hiddenFor: userId }
    });

    // Hide all messages for this user
    const updateResult = await Message.updateMany(
      {
        $or: [
          { conversation: conversationId },
          { conversationId: conversationId }
        ]
      },
      { $addToSet: { deletedFor: userId } }
    );

    res.json({
      success: true,
      message: 'Conversation deleted successfully',
      messagesHidden: updateResult.modifiedCount
    });
  } catch (error) {
    console.error('❌ Delete conversation error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error deleting conversation'
    });
  }
};

/**
 * Send chat request (Backend1 style)
 */
export const sendChatRequest = async (req, res) => {
  try {
    const { from, toPhone } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    if (!from || !toPhone) {
      return res.status(400).json({
        success: false,
        error: 'missing_fields',
        message: 'From and toPhone are required'
      });
    }

    if (String(from) !== String(userId)) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Access denied'
      });
    }

    const to = await uidByPhone(toPhone);
    if (!to) {
      return res.status(404).json({
        success: false,
        error: 'user_not_found',
        message: `No user found for phone: ${toPhone}`
      });
    }

    const participants = pair(from, to);
    let conversation = await Conversation.findOne({
      $or: [
        { participants: { $all: participants, $size: 2 } },
        { members: { $all: participants, $size: 2 } }
      ],
      status: { $in: ['pending', 'active'] },
      isGroup: false
    });

    if (!conversation) {
      conversation = await Conversation.create({
        participants,
        members: participants,
        status: 'pending',
        createdBy: from,
        isGroup: false,
        lastMessageAt: null
      });
    }

    // Emit to recipient
    const io = req.app.get('io');
    if (io) {
      io.to(String(to)).emit('chat_request', {
        _id: String(conversation._id),
        from: String(from),
        to: String(to),
        status: conversation.status,
        createdAt: conversation.createdAt
      });
    }

    res.json({
      success: true,
      ok: true,
      conversation
    });
  } catch (error) {
    console.error('❌ Send chat request error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error sending chat request'
    });
  }
};

/**
 * Get chat requests
 */
export const getChatRequests = async (req, res) => {
  try {
    const { me, status = 'pending' } = req.query;
    const userId = req.user.id || req.user.uid || req.user.userId;
    const targetUserId = me || userId;

    if (String(targetUserId) !== String(userId)) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Access denied'
      });
    }

    const conversations = await Conversation.find({
      $or: [
        { participants: targetUserId },
        { members: targetUserId }
      ],
      status
    })
      .populate('participants', 'name phone avatar avatarUrl')
      .populate('members', 'name phone avatar avatarUrl')
      .sort({ createdAt: -1 })
      .lean();

    res.json({
      success: true,
      conversations
    });
  } catch (error) {
    console.error('❌ Get chat requests error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching chat requests'
    });
  }
};

/**
 * Accept chat request
 */
export const acceptChatRequest = async (req, res) => {
  try {
    const { id } = req.params;
    const { me } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;
    const targetUserId = me || userId;

    if (String(targetUserId) !== String(userId)) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Access denied'
      });
    }

    const conversation = await Conversation.findById(id);
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

    conversation.status = 'active';
    if (!conversation.lastMessageAt) {
      conversation.lastMessageAt = new Date();
    }
    await conversation.save();

    // Emit to all participants
    const io = req.app.get('io');
    if (io) {
      members.forEach(p => {
        const partner = members.find(x => String(x) !== String(p));
        io.to(String(p)).emit('chat_request_accepted', {
          conversationId: String(conversation._id),
          partnerId: partner ? String(partner) : undefined
        });
      });
    }

    res.json({
      success: true,
      ok: true,
      conversation
    });
  } catch (error) {
    console.error('❌ Accept chat request error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error accepting chat request'
    });
  }
};

/**
 * Decline chat request
 */
export const declineChatRequest = async (req, res) => {
  try {
    const { id } = req.params;
    const { me } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;
    const targetUserId = me || userId;

    if (String(targetUserId) !== String(userId)) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Access denied'
      });
    }

    const conversation = await Conversation.findById(id);
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

    conversation.status = 'declined';
    await conversation.save();

    // Emit to requester
    const io = req.app.get('io');
    if (io && conversation.createdBy) {
      io.to(String(conversation.createdBy)).emit('chat_request_declined', {
        conversationId: String(conversation._id),
        by: String(userId)
      });
    }

    res.json({
      success: true,
      ok: true,
      conversation
    });
  } catch (error) {
    console.error('❌ Decline chat request error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error declining chat request'
    });
  }
};

/**
 * Start chat directly (Backend1 style)
 */
export const startChat = async (req, res) => {
  try {
    const { from, toPhone } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    if (!from || !toPhone) {
      return res.status(400).json({
        success: false,
        error: 'missing_fields',
        message: 'From and toPhone are required'
      });
    }

    if (String(from) !== String(userId)) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: 'Access denied'
      });
    }

    const to = await uidByPhone(toPhone);
    if (!to) {
      return res.status(404).json({
        success: false,
        error: 'user_not_found',
        message: `No user found for phone: ${toPhone}`
      });
    }

    const participants = pair(from, to);

    // Find existing conversation (any status)
    let conversation = await Conversation.findOne({
      $or: [
        { participants: { $all: participants, $size: 2 } },
        { members: { $all: participants, $size: 2 } }
      ],
      isGroup: false
    });

    if (!conversation) {
      // Create new active conversation
      conversation = await Conversation.create({
        participants,
        members: participants,
        status: 'active',
        createdBy: from,
        isGroup: false,
        lastMessageAt: null
      });
    } else if (conversation.status !== 'active') {
      // Upgrade to active
      conversation.status = 'active';
      await conversation.save();
    }

    await conversation.populate([
      { path: 'participants', select: 'name phone avatar avatarUrl isOnline lastSeen' },
      { path: 'members', select: 'name phone avatar avatarUrl isOnline lastSeen' }
    ]);

    res.json({
      success: true,
      ok: true,
      conversation: {
        _id: String(conversation._id),
        participants: conversation.participants.map(p => String(p._id || p)),
        members: conversation.members.map(m => String(m._id || m)),
        status: conversation.status,
        createdBy: String(conversation.createdBy),
        lastMessageAt: conversation.lastMessageAt,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt
      }
    });
  } catch (error) {
    console.error('❌ Start chat error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error starting chat'
    });
  }
};

/**
 * Sync contacts (Backend1 style)
 */
export const syncContacts = async (req, res) => {
  try {
    const { contacts } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    if (!Array.isArray(contacts)) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Contacts must be an array'
      });
    }

    // Normalize phone numbers
    const normalizedPhones = contacts
      .map(c => {
        const phone = (c && typeof c === 'object' ? c.phone : c)?.toString().trim();
        return phone ? normalizePhone(phone) : null;
      })
      .filter(Boolean)
      .filter((phone, index, self) => self.indexOf(phone) === index); // Remove duplicates

    if (normalizedPhones.length === 0) {
      return res.json({
        success: true,
        matches: []
      });
    }

    // Find users with matching phone numbers
    const users = await User.find({
      phone: { $in: normalizedPhones },
      _id: { $ne: userId }
    })
      .select('_id name phone avatar avatarUrl')
      .lean();

    const matches = users.map(u => ({
      id: String(u._id),
      name: u.name,
      phone: u.phone,
      avatarUrl: u.avatarUrl || u.avatar || null,
      avatar: u.avatar || u.avatarUrl || null
    }));

    res.json({
      success: true,
      matches
    });
  } catch (error) {
    console.error('❌ Sync contacts error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error syncing contacts'
    });
  }
};

// Export default object for route compatibility
export default {
  getConversations,
  createConversation,
  getConversationDetails,
  deleteConversation,
  sendChatRequest,
  getChatRequests,
  acceptChatRequest,
  declineChatRequest,
  startChat,
  syncContacts
};

