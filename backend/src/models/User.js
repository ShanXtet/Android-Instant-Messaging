import mongoose from 'mongoose';

// Normalize phone number helper
const normalizePhone = (phone) => {
  if (!phone) return '';
  const raw = phone.toString().trim();
  const digits = raw.replace(/\D/g, '');
  if (!digits) return '';
  return `+${digits}`;
};

const userSchema = new mongoose.Schema({
  phone: { 
    type: String, 
    required: true,
    set: normalizePhone
  },
  password: { 
    type: String 
  },
  passwordHash: {
    type: String
  },
  name: { 
    type: String,
    required: [true, 'Name is required'],
    trim: true,
    minlength: [1, 'Name cannot be empty']
  },
  username: { 
    type: String 
  },
  avatar: { 
    type: String 
  },
  avatarUrl: {
    type: String
  },
  bio: { 
    type: String,
    maxlength: [500, 'Bio cannot exceed 500 characters']
  },
  dateOfBirth: { 
    type: Date 
  },
  email: {
    type: String
  },
  isOnline: { 
    type: Boolean, 
    default: false,
    index: true
  },
  lastSeen: { 
    type: Date, 
    default: Date.now,
    index: true
  },
  googleSub: {
    type: String,
    sparse: true
  }
}, { 
  timestamps: true,
  collection: 'users'
});

// Pre-save hook to ensure phone is always normalized
userSchema.pre('save', function(next) {
  if (this.phone) {
    this.phone = normalizePhone(this.phone);
  }
  // Normalize avatar/avatarUrl
  if (this.avatar && !this.avatarUrl) {
    this.avatarUrl = this.avatar;
  }
  if (this.avatarUrl && !this.avatar) {
    this.avatar = this.avatarUrl;
  }
  next();
});

// Indexes
userSchema.index({ phone: 1 }, { unique: true });
userSchema.index({ isOnline: 1, lastSeen: -1 });

// Static method to normalize phone
userSchema.statics.normalizePhone = normalizePhone;

export default mongoose.models.User || mongoose.model('User', userSchema);

