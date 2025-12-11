import mongoose from 'mongoose';

const groupSchema = new mongoose.Schema({
  name: { 
    type: String, 
    required: [true, 'Group name is required'],
    trim: true,
    maxlength: [100, 'Group name cannot exceed 100 characters']
  },
  description: {
    type: String,
    trim: true,
    maxlength: [500, 'Description cannot exceed 500 characters']
  },
  admin: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true
  },
  admins: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  participants: [{ 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User',
    required: true
  }],
  members: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  avatar: { 
    type: String 
  },
  avatarUrl: {
    type: String
  },
  // Link to conversation (1:1 relationship)
  conversation: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Conversation',
    unique: true,
    index: true
  },
  conversationId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Conversation',
    unique: true,
    index: true
  },
  // Group settings
  settings: {
    onlyAdminsCanSendMessages: {
      type: Boolean,
      default: false
    },
    onlyAdminsCanAddMembers: {
      type: Boolean,
      default: false
    },
    isPublic: {
      type: Boolean,
      default: false
    },
    inviteLink: {
      type: String
    }
  },
  // Group metadata
  memberCount: {
    type: Number,
    default: 0
  },
  lastActivity: {
    type: Date,
    default: Date.now
  }
}, { 
  timestamps: true 
});

// Indexes for better performance
groupSchema.index({ admin: 1 });
groupSchema.index({ participants: 1 });
groupSchema.index({ members: 1 });
groupSchema.index({ 'settings.inviteLink': 1 }, { unique: true, sparse: true });
groupSchema.index({ lastActivity: -1 });

// Pre-save middleware to sync fields
groupSchema.pre('save', function(next) {
  // Sync participants/members
  if (this.participants && this.participants.length > 0 && (!this.members || this.members.length === 0)) {
    this.members = this.participants;
  }
  if (this.members && this.members.length > 0 && (!this.participants || this.participants.length === 0)) {
    this.participants = this.members;
  }
  
  // Sync avatar/avatarUrl
  if (this.avatar && !this.avatarUrl) {
    this.avatarUrl = this.avatar;
  }
  if (this.avatarUrl && !this.avatar) {
    this.avatar = this.avatarUrl;
  }
  
  // Sync conversation/conversationId
  if (this.conversation && !this.conversationId) {
    this.conversationId = this.conversation;
  }
  if (this.conversationId && !this.conversation) {
    this.conversation = this.conversationId;
  }
  
  // Ensure admin is in participants and admins arrays
  if (this.admin) {
    const adminId = this.admin.toString ? this.admin.toString() : this.admin;
    const adminInParticipants = this.participants.some(p => {
      const pid = p.toString ? p.toString() : p;
      return pid === adminId;
    });
    if (!adminInParticipants) {
      this.participants.push(this.admin);
    }
    
    // Add to admins array if not present
    if (!this.admins || this.admins.length === 0) {
      this.admins = [this.admin];
    } else {
      const adminInAdmins = this.admins.some(a => {
        const aid = a.toString ? a.toString() : a;
        return aid === adminId;
      });
      if (!adminInAdmins) {
        this.admins.push(this.admin);
      }
    }
  }
  
  // Update member count
  this.memberCount = this.participants ? this.participants.length : 0;
  
  // Update last activity
  this.lastActivity = new Date();
  
  next();
});

// Instance methods
groupSchema.methods.isAdmin = function(userId) {
  const uid = userId.toString ? userId.toString() : userId;
  return this.admin.toString() === uid || 
         (this.admins && this.admins.some(a => a.toString() === uid));
};

groupSchema.methods.isMember = function(userId) {
  const uid = userId.toString ? userId.toString() : userId;
  return this.participants.some(p => p.toString() === uid) ||
         this.members.some(m => m.toString() === uid);
};

groupSchema.methods.addMember = async function(userId) {
  const uid = userId.toString ? userId.toString() : userId;
  
  // Check if already a member
  if (this.isMember(userId)) {
    return false;
  }
  
  this.participants.push(userId);
  if (this.members && !this.members.some(m => m.toString() === uid)) {
    this.members.push(userId);
  }
  
  await this.save();
  return true;
};

groupSchema.methods.removeMember = async function(userId) {
  const uid = userId.toString ? userId.toString() : userId;
  
  // Cannot remove admin
  if (this.isAdmin(userId)) {
    throw new Error('Cannot remove admin from group');
  }
  
  this.participants = this.participants.filter(p => p.toString() !== uid);
  if (this.members) {
    this.members = this.members.filter(m => m.toString() !== uid);
  }
  
  await this.save();
  return true;
};

// Static methods
groupSchema.statics.generateInviteLink = function() {
  return Math.random().toString(36).substring(2, 15) + 
         Math.random().toString(36).substring(2, 15);
};

export default mongoose.models.Group || mongoose.model('Group', groupSchema);

