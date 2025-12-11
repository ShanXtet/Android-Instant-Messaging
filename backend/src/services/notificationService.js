import Notification from '../models/Notification.js';
import User from '../models/User.js';
import Message from '../models/Message.js';
import Conversation from '../models/Conversation.js';
import path from 'path';

/**
 * Notification Service
 * Creates and manages notifications for various events
 */
class NotificationService {
  constructor(io, presenceService) {
    this.io = io;
    this.presenceService = presenceService;
  }

  /**
   * Create message notification
   */
  async createMessageNotification(message, conversation) {
    try {
      const senderId = message.from || message.sender;
      const sender = await User.findById(senderId).select('name avatar avatarUrl').lean();
      if (!sender) return [];

      const preview = this.buildMessagePreview(message);
      const recipients = (conversation.participants || conversation.members || []).filter(
        (memberId) => String(memberId) !== String(senderId)
      );

      if (!recipients.length) return [];

      const notifications = [];

      for (const recipientId of recipients) {
        const notification = await Notification.create({
          recipient: recipientId,
          sender: senderId,
          type: 'new_message',
          title: `${sender.name || 'Someone'} sent you a message`,
          body: preview,
          relatedMessage: message._id,
          relatedConversation: conversation._id,
          priority: 'normal',
          data: {
            conversationId: String(conversation._id),
            messageId: String(message._id),
            senderName: sender.name || 'Someone',
            senderAvatar: sender.avatar || sender.avatarUrl || null,
            messageType: message.type || 'text',
            media: message.media || message.fileUrl || message.voice?.url || null,
            content: message.content || message.text || '',
            preview
          }
        });

        await notification.populate([
          { path: 'sender', select: 'name avatar avatarUrl' },
          { path: 'recipient', select: 'name avatar avatarUrl' }
        ]);

        notifications.push(notification);

        // Emit real-time notification
        if (this.presenceService) {
          this.presenceService.sendToUser(recipientId, 'notification:new', notification.toObject());
        }
      }

      return notifications;
    } catch (error) {
      console.error('❌ Error creating message notifications:', error);
      return [];
    }
  }

  /**
   * Build message preview text
   */
  buildMessagePreview(message) {
    const type = (message.type || '').toLowerCase();
    const content = (message.content || message.text || '').trim();
    const hasVoice = type === 'voice' || Boolean(message.voice && (message.voice.url || message.voice.waveform?.length));

    if (hasVoice) {
      return '🎙️ Voice message';
    }

    if (type === 'image') {
      return '📷 Photo';
    }
    if (type === 'video') {
      return '🎬 Video';
    }
    if (type === 'file') {
      return '📎 File';
    }
    if (type === 'audio') {
      return '🎧 Audio message';
    }
    if (type === 'location') {
      return '📍 Location';
    }
    if (type === 'contact') {
      return '👤 Contact';
    }
    if (type === 'call_activity' || message.callActivity) {
      return '📞 Call';
    }

    if (content.length) {
      return content.length > 120 ? `${content.slice(0, 117)}…` : content;
    }

    if (message.media || message.fileUrl) {
      const ext = path.extname(message.media || message.fileUrl || '').toLowerCase();
      if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].includes(ext)) return '📷 Photo';
      if (['.mp4', '.mov', '.webm', '.avi'].includes(ext)) return '🎬 Video';
      if (['.mp3', '.wav', '.aac', '.m4a'].includes(ext)) return '🎧 Audio message';
    }

    return 'New message';
  }

  /**
   * Create group activity notification
   */
  async createGroupActivityNotification(groupId, activityType, userId, targetUserId) {
    try {
      const user = await User.findById(userId).select('name avatar avatarUrl').lean();
      if (!user) return null;

      const messages = {
        added_to_group: {
          title: 'Added to group',
          body: `${user.name} added you to a group`
        },
        removed_from_group: {
          title: 'Removed from group',
          body: `${user.name} removed you from a group`
        },
        group_created: {
          title: 'New group',
          body: `${user.name} created a new group`
        }
      };

      const { title, body } = messages[activityType] || {
        title: 'Group activity',
        body: `${user.name} performed a group action`
      };

      const notification = await Notification.create({
        recipient: targetUserId,
        sender: userId,
        type: 'group_activity',
        title,
        body,
        relatedGroup: groupId,
        data: {
          groupId: String(groupId),
          activityType,
          senderName: user.name
        }
      });

      await notification.populate([
        { path: 'sender', select: 'name avatar avatarUrl' },
        { path: 'recipient', select: 'name avatar avatarUrl' }
      ]);

      // Emit real-time notification
      if (this.presenceService) {
        this.presenceService.sendToUser(targetUserId, 'notification:new', notification.toObject());
      }

      return notification;
    } catch (error) {
      console.error('❌ Error creating group activity notification:', error);
      return null;
    }
  }

  /**
   * Get user notifications
   */
  async getUserNotifications(userId, options = {}) {
    const { page = 1, limit = 20, type } = options;
    
    const query = { recipient: userId };
    if (type) query.type = type;

    const notifications = await Notification.find(query)
      .populate('sender', 'name avatar avatarUrl')
      .populate('recipient', 'name avatar avatarUrl')
      .populate('relatedMessage', 'content type media')
      .populate('relatedConversation', 'participants members')
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip((parseInt(page) - 1) * parseInt(limit));

    const total = await Notification.countDocuments(query);

    return {
      notifications,
      pagination: {
        totalPages: Math.ceil(total / limit),
        currentPage: page,
        total,
        limit
      }
    };
  }

  /**
   * Mark notification as read
   */
  async markAsRead(notificationId, userId) {
    const notification = await Notification.findOneAndUpdate(
      { _id: notificationId, recipient: userId },
      { isRead: true, readAt: new Date() },
      { new: true }
    ).populate('sender', 'name avatar avatarUrl');

    return notification;
  }

  /**
   * Mark all notifications as read
   */
  async markAllAsRead(userId) {
    const result = await Notification.updateMany(
      { recipient: userId, isRead: false },
      { isRead: true, readAt: new Date() }
    );

    return result.modifiedCount;
  }

  /**
   * Get unread count
   */
  async getUnreadCount(userId) {
    return await Notification.countDocuments({
      recipient: userId,
      isRead: false
    });
  }
}

export default NotificationService;

