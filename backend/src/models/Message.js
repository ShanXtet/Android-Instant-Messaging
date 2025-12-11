import mongoose from 'mongoose';

const reactionSchema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  reaction: { type: String, required: true },
  timestamp: { type: Date, default: Date.now }
});

const messageSchema = new mongoose.Schema({
  // Unified: support both from/to (Backend1) and sender (Backend)
  from: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true, 
    index: true 
  },
  to: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    index: true
  },
  sender: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    index: true
  },
  
  // Conversation reference
  conversation: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Conversation', 
    index: true 
  },
  conversationId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Conversation',
    index: true
  },
  
  // Message content - unified field names
  text: { 
    type: String, 
    trim: true, 
    maxlength: 4000 
  },
  content: {
    type: String,
    trim: true,
    maxlength: 4000
  },
  
  // Message type
  type: { 
    type: String, 
    enum: ['text', 'image', 'video', 'file', 'audio', 'location', 'contact', 'voice'], 
    default: 'text' 
  },
  messageType: {
    type: String
  },
  
  // Status (Backend style)
  status: { 
    type: String, 
    enum: ['sent', 'delivered', 'seen', 'read'], 
    default: 'sent',
    index: true
  },
  readAt: { 
    type: Date 
  },
  readBy: [{ 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User' 
  }],
  
  // File attachments (unified)
  media: { 
    type: String 
  },
  fileUrl: { 
    type: String 
  },
  fileName: { 
    type: String 
  },
  fileType: { 
    type: String 
  },
  audioDuration: { 
    type: Number 
  },
  
  // Voice messages
  voice: {
    url: { type: String },
    duration: { type: Number },
    waveform: [{ type: Number }],
    mimeType: { type: String },
    size: { type: Number }
  },
  
  // Soft delete (unified)
  deleted: { 
    type: Boolean, 
    default: false, 
    index: true 
  },
  isDeleted: {
    type: Boolean,
    default: false,
    index: true
  },
  deletedFor: [{ 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User' 
  }],
  deletedAt: { 
    type: Date 
  },
  
  // Message editing
  edited: { 
    type: Boolean, 
    default: false 
  },
  editedAt: { 
    type: Date 
  },
  originalContent: { 
    type: String 
  },
  
  // Reply functionality
  replyTo: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'Message' 
  },
  replyToMessage: { 
    type: mongoose.Schema.Types.Mixed 
  },
  
  // Reactions
  reactions: [reactionSchema],
  
  // Forwarding
  forwarded: { 
    type: Boolean, 
    default: false 
  },
  forwardedFrom: { 
    type: String 
  },
  
  // Call activity metadata (Backend1)
  callActivity: { 
    type: Boolean, 
    default: false 
  },
  callType: { 
    type: String 
  },
  callStatus: { 
    type: String 
  },
  isVideoCall: { 
    type: Boolean, 
    default: false 
  },
  callStartTime: { 
    type: Date 
  },
  callDuration: { 
    type: Number 
  },
  
  // Metadata
  metadata: {
    fileSize: Number,
    duration: Number,
    location: {
      latitude: Number,
      longitude: Number,
      address: String
    },
    contact: {
      name: String,
      phone: String,
      email: String
    }
  }
}, { 
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true }
});

// Virtual for reply message
messageSchema.virtual('replyMessage', {
  ref: 'Message',
  localField: 'replyTo',
  foreignField: '_id',
  justOne: true
});

// Pre-save middleware to sync fields
messageSchema.pre('save', function(next) {
  // Sync from/sender
  if (this.from && !this.sender) {
    this.sender = this.from;
  }
  if (this.sender && !this.from) {
    this.from = this.sender;
  }
  
  // Sync conversation/conversationId
  if (this.conversation && !this.conversationId) {
    this.conversationId = this.conversation;
  }
  if (this.conversationId && !this.conversation) {
    this.conversation = this.conversationId;
  }
  
  // Sync text/content
  if (this.text && !this.content) {
    this.content = this.text;
  }
  if (this.content && !this.text) {
    this.text = this.content;
  }
  
  // Sync deleted/isDeleted
  if (this.deleted && !this.isDeleted) {
    this.isDeleted = true;
  }
  if (this.isDeleted && !this.deleted) {
    this.deleted = true;
  }
  
  // Handle edited messages
  if (this.isModified('content') || this.isModified('text')) {
    if (!this.isNew && !this.originalContent) {
      this.originalContent = this.content || this.text;
    }
    if (!this.isNew) {
      this.edited = true;
      this.editedAt = new Date();
    }
  }
  
  next();
});

// Indexes for better performance
messageSchema.index({ conversation: 1, createdAt: -1 });
messageSchema.index({ conversationId: 1, createdAt: -1 });
messageSchema.index({ from: 1, to: 1, createdAt: 1 });
messageSchema.index({ from: 1, createdAt: -1 });
messageSchema.index({ sender: 1, createdAt: -1 });
messageSchema.index({ deleted: 1, isDeleted: 1 });
messageSchema.index({ createdAt: 1 });

export default mongoose.models.Message || mongoose.model('Message', messageSchema);

