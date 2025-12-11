import mongoose from 'mongoose';

const conversationSchema = new mongoose.Schema({
  // Participants (Backend1 uses participants, Backend uses members)
  participants: [{ 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true 
  }],
  members: [{ 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User' 
  }],
  
  // Conversation type
  isGroup: { 
    type: Boolean, 
    default: false 
  },
  status: { 
    type: String, 
    enum: ['pending', 'active', 'declined', 'blocked'], 
    default: 'active',
    index: true
  },
  
  // Group info (if group conversation)
  name: { 
    type: String 
  },
  admin: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User' 
  },
  avatar: { 
    type: String 
  },
  
  // Conversation metadata
  createdBy: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User' 
  },
  lastMessage: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Message' 
  },
  lastMessageAt: { 
    type: Date,
    index: true
  },
  
  // Unique key for direct conversations (Backend style)
  participantKey: { 
    type: String
  },
  
  // Hidden/archived conversations
  hiddenFor: [{ 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User' 
  }],
  
  // Link to Group (for group conversations)
  group: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Group'
  },
  groupId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Group'
  },
  
  // Cursor-based receipts (Backend1 style - more efficient)
  deliveredUpTo: { 
    type: Map, 
    of: Date, 
    default: {} 
  },
  readUpTo: { 
    type: Map, 
    of: Date, 
    default: {} 
  }
}, { 
  timestamps: true 
});

// Ensure unique direct conversations using participantKey (Backend style)
conversationSchema.index(
  { participantKey: 1 },
  { 
    unique: true, 
    partialFilterExpression: { 
      isGroup: false, 
      participantKey: { $exists: true } 
    } 
  }
);

// Indexes for efficient queries
conversationSchema.index({ participants: 1, status: 1 });
conversationSchema.index({ members: 1, status: 1 });
conversationSchema.index({ status: 1, lastMessageAt: -1, updatedAt: -1 });
conversationSchema.index({ hiddenFor: 1 });

  // Pre-save middleware to sync participants/members
conversationSchema.pre('save', function(next) {
  // Sync participants/members
  if (this.participants && this.participants.length > 0 && (!this.members || this.members.length === 0)) {
    this.members = this.participants;
  }
  if (this.members && this.members.length > 0 && (!this.participants || this.participants.length === 0)) {
    this.participants = this.members;
  }
  
  // Sync group/groupId
  if (this.group && !this.groupId) {
    this.groupId = this.group;
  }
  if (this.groupId && !this.group) {
    this.group = this.groupId;
  }
  
  // If group is set, ensure isGroup is true
  if (this.group || this.groupId) {
    this.isGroup = true;
  }
  
  // Generate participantKey for direct conversations if not set
  if (!this.isGroup && this.participants && this.participants.length === 2 && !this.participantKey) {
    const sorted = this.participants.map(p => p.toString()).sort();
    this.participantKey = sorted.join(':');
  }
  
  // Set default status if not set
  if (!this.status) {
    this.status = this.isGroup ? 'active' : 'active';
  }
  
  next();
});

export default mongoose.models.Conversation || mongoose.model('Conversation', conversationSchema);

