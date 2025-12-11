import express from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import User from './models/User.js';

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

const sign = (uid) => jwt.sign({ uid: String(uid) }, JWT_SECRET, { expiresIn: '7d' });

// In-memory OTP storage (in production, use Redis or MongoDB)
const otpStore = new Map(); // { sessionId: { phone, otp, expiresAt } }

// Clean up expired OTPs every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [sessionId, data] of otpStore.entries()) {
    if (data.expiresAt < now) {
      otpStore.delete(sessionId);
    }
  }
}, 5 * 60 * 1000);

// Generate 6-digit OTP
const generateOTP = () => {
  return crypto.randomInt(100000, 999999).toString();
};

// Normalize phone number (remove spaces/dashes and ensure + + digits)
// Examples:
//  "1111111111"      -> "+1111111111"
//  "+111 111 1111"   -> "+1111111111"
//  "  +111-111-1111" -> "+1111111111"
const normalizePhone = (phone) => {
  if (!phone) return '';
  const raw = phone.toString().trim();
  const digits = raw.replace(/\D/g, ''); // keep digits only
  if (!digits) return '';
  return `+${digits}`;
};

// Email-based registration removed - use phone + OTP registration only

// Email-based registration preview removed - use phone + OTP registration only

// Username/phone + password login (uses 'name' OR phone and passwordHash)
router.post('/login', async (req, res) => {
  try {
    const { name, password } = req.body || {};

    if (!name || !password) {
      return res.status(400).json({ error: 'missing', message: 'name/phone and password are required' });
    }

    const identifier = name.toString().trim();
    const normalizedPhone = normalizePhone(identifier);

    // Try to find user by exact name OR by phone
    const user = await User.findOne({
      $or: [
        { name: identifier },
        { phone: normalizedPhone },
      ],
    }).lean();

    if (!user || !user.passwordHash) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const ok = await bcrypt.compare(password.toString(), user.passwordHash || '');
    if (!ok) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const token = sign(user._id);

    return res.json({
      token,
      user: {
        id: String(user._id),
        name: user.name,
        phone: user.phone || null,
        avatarUrl: user.avatarUrl || null,
        bio: user.bio || null,
      },
    });
  } catch (e) {
    console.error('Login error:', e);
    return res.status(500).json({ error: 'server_error', message: e.message });
  }
});

// Send OTP to phone number
router.post('/send-otp', async (req, res) => {
  try {
    const { phone } = req.body || {};
    
    if (!phone) {
      console.log('❌ Send OTP: Missing phone number');
      return res.status(400).json({ error: 'missing' });
    }
    
    const normalizedPhone = normalizePhone(phone);
    
    console.log('📞 Send OTP request:', { 
      original: phone, 
      normalized: normalizedPhone,
      normalizedLength: normalizedPhone.length 
    });
    
    // Validate phone number format (at least 10 digits)
    if (normalizedPhone.length < 10 || !/^\+?\d{10,}$/.test(normalizedPhone)) {
      console.log('❌ Send OTP: Invalid phone format:', normalizedPhone);
      return res.status(400).json({ error: 'invalid_phone' });
    }
    
    // Check if phone number already registered (exact match with normalized phone)
    const exists = await User.findOne({ phone: normalizedPhone });
    if (exists) {
      console.log('❌ Send OTP: Phone already registered:', {
        searchedPhone: normalizedPhone,
        searchedLength: normalizedPhone.length,
        foundUser: {
          id: String(exists._id),
          name: exists.name,
          phone: exists.phone,
          phoneLength: exists.phone?.length
        },
        exactMatch: exists.phone === normalizedPhone
      });
      return res.status(409).json({ error: 'phone_taken' });
    }
    
    console.log('✅ Send OTP: Phone number is available:', normalizedPhone);
    
    // Generate OTP and session ID
    const otp = generateOTP();
    const sessionId = crypto.randomBytes(16).toString('hex');
    const expiresAt = Date.now() + 5 * 60 * 1000; // 5 minutes
    
    // Store OTP
    otpStore.set(sessionId, {
      phone: normalizedPhone,
      otp,
      expiresAt,
    });
    
    // Log OTP to console for testing (always show in terminal)
    console.log('═══════════════════════════════════════════════════');
    console.log('📱 OTP GENERATED FOR TESTING');
    console.log('═══════════════════════════════════════════════════');
    console.log('Phone Number:', normalizedPhone);
    console.log('Session ID:', sessionId);
    console.log('OTP Code:', otp);
    console.log('Expires At:', new Date(expiresAt).toISOString());
    console.log('═══════════════════════════════════════════════════');
    
    // TODO: In production, send OTP via SMS service (Twilio, AWS SNS, etc.)
    // For now, we'll return it in the response for testing
    // In production, remove the otp from the response
    res.status(200).json({
      sessionId,
      message: 'OTP sent successfully',
      // Always return OTP for testing (remove in production)
      otp: otp,
    });
    
    console.log('✅ Send OTP response sent');
  } catch (error) {
    console.error('❌ Send OTP error:', error);
    res.status(500).json({ error: 'server_error', message: error.message });
  }
});

// Verify OTP and register user (with optional password)
router.post('/verify-otp-register', async (req, res) => {
  try {
    const { name, phone, otp, sessionId, password } = req.body || {};
    
    // Validate input
    if (!name || !phone || !otp || !sessionId) {
      console.log('❌ Verify OTP: Missing fields', {
        name: !!name,
        phone: !!phone,
        otp: !!otp,
        sessionId: !!sessionId,
      });
      return res.status(400).json({ error: 'missing' });
    }
    
    // Validate OTP format (6 digits)
    if (!/^\d{6}$/.test(otp)) {
      return res.status(400).json({ error: 'invalid_otp_format' });
    }
    
    const normalizedPhone = normalizePhone(phone);
    
    // Get stored OTP data
    const storedData = otpStore.get(sessionId);
    if (!storedData) {
      console.log('❌ Verify OTP: Invalid session ID:', sessionId);
      return res.status(400).json({ error: 'invalid_session' });
    }
    
    // Check if OTP expired
    if (Date.now() > storedData.expiresAt) {
      console.log('❌ Verify OTP: OTP expired');
      otpStore.delete(sessionId);
      return res.status(400).json({ error: 'expired_otp' });
    }
    
    // Use the phone from stored OTP session (more reliable than request body)
    const sessionPhone = storedData.phone;
    const requestPhone = normalizedPhone;
    
    console.log('📞 Verify OTP phone comparison:', {
      sessionPhone: sessionPhone,
      requestPhone: requestPhone,
      match: sessionPhone === requestPhone
    });
    
    // Verify phone number matches (use session phone as source of truth)
    if (storedData.phone !== normalizedPhone) {
      console.log('❌ Verify OTP: Phone mismatch', {
        sessionPhone: storedData.phone,
        requestPhone: normalizedPhone,
        sessionLength: storedData.phone?.length,
        requestLength: normalizedPhone?.length
      });
      return res.status(400).json({ error: 'phone_mismatch' });
    }
    
    // Verify OTP code
    if (storedData.otp !== otp) {
      console.log('❌ Verify OTP: Invalid OTP code');
      console.log('   Expected:', storedData.otp);
      console.log('   Received:', otp);
      return res.status(400).json({ error: 'invalid_otp' });
    }
    
    console.log('✅ OTP verified successfully for phone:', sessionPhone);
    
    // Check if phone number already registered (use session phone as source of truth)
    // First, let's check all users to see what's in the database
    const allUsers = await User.find({}).select('phone name').lean();
    console.log('🔍 All users in database before check:', allUsers.map(u => ({ phone: u.phone, name: u.name })));
    
    // Use session phone (the one that was verified) for the check
    const exists = await User.findOne({ phone: sessionPhone });
    if (exists) {
      console.log('❌ Verify OTP: Phone already registered:', {
        searchedPhone: sessionPhone,
        searchedLength: sessionPhone.length,
        foundUser: {
          id: String(exists._id),
          name: exists.name,
          phone: exists.phone,
          phoneLength: exists.phone?.length
        },
        phoneMatch: exists.phone === sessionPhone,
        phoneBytes: {
          searched: Buffer.from(sessionPhone).toString('hex'),
          found: Buffer.from(exists.phone || '').toString('hex')
        }
      });
      otpStore.delete(sessionId);
      return res.status(409).json({ 
        error: 'phone_taken',
        message: `Phone number ${sessionPhone} is already registered`,
        existingUser: {
          id: String(exists._id),
          name: exists.name
        }
      });
    }
    
    console.log('✅ Verify OTP: Phone number is available for registration:', sessionPhone);
    
    // Prepare user payload
    const userPayload = {
      name: name.trim(),
      phone: sessionPhone,
    };

    // If password is provided, hash and store it
    if (password && password.toString().trim().length >= 6) {
      console.log('🔐 Hashing password for phone-based registration');
      const passwordHash = await bcrypt.hash(password.toString().trim(), 10);
      userPayload.passwordHash = passwordHash;
    }

    console.log('👤 Creating user with phone:', { name: name.trim(), phone: sessionPhone });
    const user = await User.create(userPayload);
    
    console.log('✅ User created successfully:', {
      id: String(user._id),
      name: user.name,
      phone: user.phone,
      hasPasswordHash: !!user.passwordHash,
    });
    
    // Verify user was saved
    const savedUser = await User.findById(user._id);
    if (!savedUser) {
      console.error('❌ CRITICAL: User was not saved to database!');
      return res.status(500).json({ error: 'user_not_saved' });
    }
    
    // Delete used OTP
    otpStore.delete(sessionId);
    
    // Generate token
    const token = sign(user._id);
    
  res.status(201).json({ 
      token,
    user: {
      id: String(user._id), 
      name: user.name, 
        phone: user.phone,
      avatarUrl: user.avatarUrl || null,
      bio: user.bio || null,
      },
  });
    
    console.log('✅ Verify OTP registration response sent');
  } catch (error) {
    console.error('❌ Verify OTP error:', error);
    
    // Handle MongoDB duplicate key error
    if (error.code === 11000) {
      return res.status(409).json({ error: 'phone_taken' });
    }
    
    // Handle validation errors
    if (error.name === 'ValidationError') {
      const messages = Object.values(error.errors).map(e => e.message).join(', ');
      console.error('Validation error:', messages);
      return res.status(400).json({ error: 'validation_error', details: messages });
    }
    
    // Generic error
    res.status(500).json({ error: 'server_error', message: error.message });
  }
});

// Send OTP for login (creates user if doesn't exist, then sends OTP)
router.post('/send-otp-login', async (req, res) => {
  try {
    const { name, phone } = req.body || {};
    
    if (!phone) {
      console.log('❌ Send OTP Login: Missing phone number');
      return res.status(400).json({ error: 'missing', message: 'phone is required' });
    }
    
    const normalizedPhone = normalizePhone(phone);
    
    // Use provided name or default to phone number
    const providedName = name && name.toString().trim().length > 0 
      ? name.toString().trim() 
      : null;
    const identifier = providedName || normalizedPhone;
    
    console.log('📞 Send OTP Login request:', { 
      name: providedName,
      originalPhone: phone, 
      normalizedPhone: normalizedPhone,
    });
    
    // Validate phone number format
    if (normalizedPhone.length < 10 || !/^\+?\d{10,}$/.test(normalizedPhone)) {
      console.log('❌ Send OTP Login: Invalid phone format:', normalizedPhone);
      return res.status(400).json({ error: 'invalid_phone' });
    }

    // Check if user exists with this phone number
    let user = await User.findOne({ phone: normalizedPhone }).lean();
    
    if (user) {
      // User exists - update name only if a name was provided and it's different
      if (providedName && user.name !== providedName) {
        console.log('📝 Updating user name:', {
          oldName: user.name,
          newName: providedName,
        });
        await User.updateOne(
          { _id: user._id },
          { $set: { name: providedName } }
        );
        user.name = providedName;
      }
      console.log('✅ Send OTP Login: User found:', {
        id: String(user._id),
        name: user.name,
        phone: user.phone,
      });
    } else {
      // User doesn't exist - create new user with provided name or phone as name
      console.log('👤 Creating new user:', {
        name: identifier,
        phone: normalizedPhone,
      });
      
      try {
        const newUser = await User.create({
          name: identifier,
          phone: normalizedPhone,
        });
        
        user = {
          _id: newUser._id,
          name: newUser.name,
          phone: newUser.phone,
        };
        
        console.log('✅ New user created:', {
          id: String(user._id),
          name: user.name,
          phone: user.phone,
        });
      } catch (createError) {
        // Handle duplicate key error (phone already exists)
        if (createError.code === 11000) {
          console.log('⚠️ Duplicate phone detected, fetching existing user');
          user = await User.findOne({ phone: normalizedPhone }).lean();
          if (user && providedName && user.name !== providedName) {
            await User.updateOne(
              { _id: user._id },
              { $set: { name: providedName } }
            );
            user.name = providedName;
          }
        } else {
          throw createError;
        }
      }
    }
    
    // Generate OTP and session ID
    const otp = generateOTP();
    const sessionId = crypto.randomBytes(16).toString('hex');
    const expiresAt = Date.now() + 5 * 60 * 1000; // 5 minutes
    
    // Store OTP with user info
    otpStore.set(sessionId, {
      phone: normalizedPhone,
      userId: String(user._id),
      otp,
      expiresAt,
      isLogin: true, // Mark as login OTP
    });
    
    // Log OTP to console for testing
    console.log('═══════════════════════════════════════════════════');
    console.log('📱 LOGIN OTP GENERATED FOR TESTING');
    console.log('═══════════════════════════════════════════════════');
    console.log('User:', user.name);
    console.log('Phone Number:', normalizedPhone);
    console.log('Session ID:', sessionId);
    console.log('OTP Code:', otp);
    console.log('Expires At:', new Date(expiresAt).toISOString());
    console.log('═══════════════════════════════════════════════════');
    
    res.status(200).json({
      sessionId,
      message: 'OTP sent successfully',
      // Always return OTP for testing (remove in production)
      otp: otp,
    });
    
    console.log('✅ Send OTP Login response sent');
  } catch (error) {
    console.error('❌ Send OTP Login error:', error);
    
    // Handle MongoDB duplicate key error
    if (error.code === 11000) {
      return res.status(409).json({ error: 'phone_taken', message: 'Phone number already registered' });
    }
    
    // Handle validation errors
    if (error.name === 'ValidationError') {
      const messages = Object.values(error.errors).map(e => e.message).join(', ');
      console.error('Validation error:', messages);
      return res.status(400).json({ error: 'validation_error', details: messages });
    }
    
    res.status(500).json({ error: 'server_error', message: error.message });
  }
});

// Verify OTP for login and return JWT token
router.post('/verify-otp-login', async (req, res) => {
  try {
    const { otp, sessionId } = req.body || {};
    
    if (!otp || !sessionId) {
      console.log('❌ Verify OTP Login: Missing fields');
      return res.status(400).json({ error: 'missing', message: 'otp and sessionId are required' });
    }
    
    // Validate OTP format (6 digits)
    if (!/^\d{6}$/.test(otp)) {
      return res.status(400).json({ error: 'invalid_otp_format' });
    }
    
    // Get stored OTP data
    const storedData = otpStore.get(sessionId);
    if (!storedData) {
      console.log('❌ Verify OTP Login: Invalid session ID:', sessionId);
      return res.status(400).json({ error: 'invalid_session' });
    }
    
    // Check if this is a login OTP
    if (!storedData.isLogin) {
      console.log('❌ Verify OTP Login: Session is not a login OTP');
      return res.status(400).json({ error: 'invalid_session_type' });
    }
    
    // Check if OTP expired
    if (Date.now() > storedData.expiresAt) {
      console.log('❌ Verify OTP Login: OTP expired');
      otpStore.delete(sessionId);
      return res.status(400).json({ error: 'expired_otp' });
    }
    
    // Verify OTP code
    if (storedData.otp !== otp) {
      console.log('❌ Verify OTP Login: Invalid OTP code');
      console.log('   Expected:', storedData.otp);
      console.log('   Received:', otp);
      return res.status(400).json({ error: 'invalid_otp' });
    }
    
    console.log('✅ OTP Login verified successfully');
    
    // Get user from stored userId
    const user = await User.findById(storedData.userId).lean();
    if (!user) {
      console.log('❌ Verify OTP Login: User not found');
      otpStore.delete(sessionId);
      return res.status(404).json({ error: 'user_not_found' });
    }
    
    // Delete used OTP
    otpStore.delete(sessionId);
    
    // Generate token
    const token = sign(user._id);
    
    console.log('✅ Login successful:', {
      id: String(user._id),
      name: user.name,
      phone: user.phone,
    });
    
    res.status(200).json({
      token,
    user: {
      id: String(user._id), 
      name: user.name, 
        phone: user.phone || null,
      avatarUrl: user.avatarUrl || null,
      bio: user.bio || null,
      },
    });
  } catch (error) {
    console.error('❌ Verify OTP Login error:', error);
    res.status(500).json({ error: 'server_error', message: error.message });
    } 
});

router.get('/me', async (req,res)=>{
  try{
    const raw = (req.headers.authorization||'').replace('Bearer ','');
    const { uid } = jwt.verify(raw, JWT_SECRET);
    const u = await User.findById(uid).lean();
    if(!u) return res.status(401).json({error:'bad_token'});
    res.json({ 
      user: {
        id: String(u._id), 
        name: u.name, 
        phone: u.phone || null,
        avatarUrl: u.avatarUrl || null,
        bio: u.bio || null,
      } 
    });
  }catch{ res.status(401).json({error:'bad_token'}); }
});

export default router;
