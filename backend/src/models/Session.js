import mongoose from 'mongoose';

const sessionSchema = new mongoose.Schema({
  userId: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true,
    index: true 
  },
  sessionId: { 
    type: String, 
    required: true, 
    unique: true,
    index: true 
  },
  device: { 
    type: String, 
    required: true,
    trim: true 
  },
  ip: { 
    type: String, 
    required: true,
    trim: true 
  },
  token: { 
    type: String, 
    required: true,
    unique: true,
    index: true 
  },
  valid: { 
    type: Boolean, 
    default: true,
    index: true 
  },
  userAgent: {
    type: String,
    trim: true
  },
  location: {
    country: String,
    city: String,
    region: String
  },
  lastActivity: {
    type: Date,
    default: Date.now,
    index: true
  },
  expiresAt: { 
    type: Date, 
    required: true
  }
}, { 
  timestamps: true 
});

// Indexes for efficient queries
sessionSchema.index({ userId: 1, valid: 1 });
sessionSchema.index({ sessionId: 1, valid: 1 });
sessionSchema.index({ token: 1, valid: 1 });
sessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 }); // TTL index for automatic cleanup

// Static method to clean up expired sessions
sessionSchema.statics.cleanupExpiredSessions = async function() {
  try {
    const result = await this.deleteMany({
      $or: [
        { valid: false },
        { expiresAt: { $lt: new Date() } }
      ]
    });
    console.log(`🧹 Cleaned up ${result.deletedCount} expired sessions`);
    return result.deletedCount;
  } catch (error) {
    console.error('❌ Error cleaning up expired sessions:', error);
    throw error;
  }
};

// Instance method to revoke session
sessionSchema.methods.revoke = async function() {
  this.valid = false;
  this.lastActivity = new Date();
  return await this.save();
};

// Instance method to update last activity
sessionSchema.methods.updateActivity = async function() {
  this.lastActivity = new Date();
  return await this.save();
};

export default mongoose.models.Session || mongoose.model('Session', sessionSchema);

