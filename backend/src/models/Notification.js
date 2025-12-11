import mongoose from 'mongoose';

const notificationSchema = new mongoose.Schema({
  recipient: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true,
    index: true
  },
  sender: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true 
  },
  type: { 
    type: String, 
    enum: [
      'new_message', 
      'group_activity', 
      'incoming_call', 
      'friend_request', 
      'message_reaction',
      'message_reply',
      'file_shared',
      'system_notification',
      'chat_request',
      'chat_request_accepted',
      'chat_request_declined'
    ], 
    required: true,
    index: true
  },
  title: { 
    type: String, 
    required: true 
  },
  body: { 
    type: String, 
    required: true 
  },
  isRead: { 
    type: Boolean, 
    default: false,
    index: true
  },
  readAt: { 
    type: Date 
  },
  relatedMessage: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Message' 
  },
  relatedConversation: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Conversation' 
  },
  relatedGroup: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Group' 
  },
  data: { 
    type: mongoose.Schema.Types.Mixed, 
    default: {} 
  },
  priority: { 
    type: String, 
    enum: ['low', 'normal', 'high', 'urgent'], 
    default: 'normal' 
  },
  expiresAt: { 
    type: Date
  }
}, { 
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true }
});

// Indexes for better performance
notificationSchema.index({ recipient: 1, isRead: 1 });
notificationSchema.index({ recipient: 1, createdAt: -1 });
notificationSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

// Virtual for time ago
notificationSchema.virtual('timeAgo').get(function() {
  const now = new Date();
  const diffInSeconds = Math.floor((now - this.createdAt) / 1000);
  
  if (diffInSeconds < 60) return 'Just now';
  if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)}m ago`;
  if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)}h ago`;
  return `${Math.floor(diffInSeconds / 86400)}d ago`;
});

// Pre-save middleware to set expiration for certain notification types
notificationSchema.pre('save', function(next) {
  if (this.type === 'incoming_call' && !this.expiresAt) {
    // Call notifications expire after 1 hour
    this.expiresAt = new Date(Date.now() + 60 * 60 * 1000);
  }
  next();
});

// Static method to get unread count for a user
notificationSchema.statics.getUnreadCount = function(userId) {
  return this.countDocuments({ 
    recipient: userId, 
    isRead: false 
  });
};

// Static method to mark all as read for a user
notificationSchema.statics.markAllAsRead = function(userId) {
  return this.updateMany(
    { recipient: userId, isRead: false },
    { isRead: true, readAt: new Date() }
  );
};

// Instance method to mark as read
notificationSchema.methods.markAsRead = function() {
  this.isRead = true;
  this.readAt = new Date();
  return this.save();
};

export default mongoose.models.Notification || mongoose.model('Notification', notificationSchema);

