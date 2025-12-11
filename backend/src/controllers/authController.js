import User from '../models/User.js';
import Otp from '../models/Otp.js';
import Session from '../models/Session.js';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import config from '../config/index.js';
import { normalizePhone } from '../utils/phoneNormalizer.js';

const generateOTP = () => {
  return crypto.randomInt(100000, 999999).toString();
};

const signToken = (userId, sessionId = null, deviceInfo = {}) => {
  const payload = {
    uid: String(userId),
    id: String(userId),
    userId: String(userId),
    _id: String(userId)
  };
  
  if (sessionId) {
    payload.sessionId = sessionId;
  }
  if (deviceInfo.device) {
    payload.device = deviceInfo.device;
  }
  if (deviceInfo.ip) {
    payload.ip = deviceInfo.ip;
  }
  
  return jwt.sign(payload, config.jwtSecret, {
    algorithm: 'HS256',
    expiresIn: config.jwtExpiry
  });
};

/**
 * Send OTP for registration
 */
export const sendOtp = async (req, res) => {
  try {
    const { phone } = req.body;
    
    if (!phone) {
      return res.status(400).json({
        success: false,
        error: 'missing',
        message: 'Phone number is required'
      });
    }
    
    const normalizedPhone = normalizePhone(phone);
    
    // Validate phone number format
    if (normalizedPhone.length < 10 || !/^\+?\d{10,}$/.test(normalizedPhone)) {
      return res.status(400).json({
        success: false,
        error: 'invalid_phone',
        message: 'Invalid phone number format'
      });
    }
    
    // Check if phone number already registered
    const exists = await User.findOne({ phone: normalizedPhone });
    if (exists) {
      return res.status(409).json({
        success: false,
        error: 'phone_taken',
        message: 'Phone number is already registered'
      });
    }
    
    // Generate OTP and session ID
    const otp = generateOTP();
    const sessionId = crypto.randomBytes(16).toString('hex');
    const expiresAt = new Date(Date.now() + config.otpExpiryMinutes * 60 * 1000);
    
    // Store OTP in database (not in-memory)
    await Otp.create({
      phone: normalizedPhone,
      otp,
      sessionId,
      expiresAt,
      isLogin: false
    });
    
    // Log OTP for development (remove in production)
    if (config.nodeEnv !== 'production') {
      console.log('═══════════════════════════════════════════════════');
      console.log('📱 OTP GENERATED FOR REGISTRATION');
      console.log('═══════════════════════════════════════════════════');
      console.log('Phone Number:', normalizedPhone);
      console.log('Session ID:', sessionId);
      console.log('OTP Code:', otp);
      console.log('Expires At:', expiresAt.toISOString());
      console.log('═══════════════════════════════════════════════════');
    }
    
    // TODO: In production, send OTP via SMS service (Twilio, AWS SNS, etc.)
    res.status(200).json({
      success: true,
      sessionId,
      message: 'OTP sent successfully',
      ...(config.nodeEnv !== 'production' && { otp }) // Only return OTP in dev
    });
  } catch (error) {
    console.error('❌ Send OTP error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Internal server error'
    });
  }
};

/**
 * Verify OTP and register user
 */
export const verifyOtpRegister = async (req, res) => {
  try {
    const { name, phone, otp, sessionId, password } = req.body;
    
    if (!name || !phone || !otp || !sessionId) {
      return res.status(400).json({
        success: false,
        error: 'missing',
        message: 'Name, phone, OTP, and sessionId are required'
      });
    }
    
    // Validate OTP format
    if (!/^\d{6}$/.test(otp)) {
      return res.status(400).json({
        success: false,
        error: 'invalid_otp_format',
        message: 'OTP must be 6 digits'
      });
    }
    
    const normalizedPhone = normalizePhone(phone);
    
    // Get stored OTP from database
    const storedOtp = await Otp.findOne({
      sessionId,
      phone: normalizedPhone,
      isLogin: false,
      used: false,
      expiresAt: { $gt: new Date() }
    });
    
    if (!storedOtp) {
      return res.status(400).json({
        success: false,
        error: 'invalid_otp',
        message: 'Invalid or expired OTP'
      });
    }
    
    // Verify OTP code
    if (storedOtp.otp !== otp) {
      return res.status(400).json({
        success: false,
        error: 'invalid_otp',
        message: 'Invalid OTP code'
      });
    }
    
    // Check if user already exists
    const existingUser = await User.findOne({ phone: normalizedPhone });
    if (existingUser) {
      await Otp.findByIdAndUpdate(storedOtp._id, { used: true });
      return res.status(409).json({
        success: false,
        error: 'phone_taken',
        message: 'Phone number is already registered'
      });
    }
    
    // Prepare user payload
    const userPayload = {
      name: name.trim(),
      phone: normalizedPhone,
      isOnline: true,
      lastSeen: new Date()
    };
    
    // Hash password if provided
    if (password && password.toString().trim().length >= 6) {
      userPayload.passwordHash = await bcrypt.hash(password.toString().trim(), 10);
    }
    
    // Create user
    const user = await User.create(userPayload);
    
    // Mark OTP as used
    await Otp.findByIdAndUpdate(storedOtp._id, { used: true });
    
    // Create session (optional - for Backend compatibility)
    const sessionIdForToken = uuidv4();
    const deviceInfo = {
      device: req.get('X-Device-Name') || req.get('User-Agent')?.split(' ')[0] || 'Unknown',
      ip: req.ip || req.connection.remoteAddress || 'Unknown',
      userAgent: req.get('User-Agent') || 'Unknown'
    };
    
    // Generate JWT token (supports both formats)
    const token = signToken(user._id, sessionIdForToken, deviceInfo);
    
    // Create session record (for Backend compatibility)
    await Session.create({
      userId: user._id,
      sessionId: sessionIdForToken,
      device: deviceInfo.device,
      ip: deviceInfo.ip,
      token,
      userAgent: deviceInfo.userAgent,
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      valid: true
    });
    
    res.status(201).json({
      success: true,
      token,
      sessionId: sessionIdForToken,
      isNewUser: true,
      user: {
        id: String(user._id),
        uid: String(user._id),
        userId: String(user._id),
        name: user.name,
        phone: user.phone,
        avatar: user.avatar || user.avatarUrl || null,
        avatarUrl: user.avatarUrl || user.avatar || null,
        bio: user.bio || null,
        isOnline: user.isOnline,
        lastSeen: user.lastSeen
      }
    });
  } catch (error) {
    console.error('❌ Verify OTP Register error:', error);
    
    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        error: 'phone_taken',
        message: 'Phone number is already registered'
      });
    }
    
    if (error.name === 'ValidationError') {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: Object.values(error.errors).map(e => e.message).join(', ')
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Internal server error'
    });
  }
};

/**
 * Send OTP for login
 */
export const sendOtpLogin = async (req, res) => {
  try {
    const { name, phone } = req.body;
    
    if (!phone) {
      return res.status(400).json({
        success: false,
        error: 'missing',
        message: 'Phone number is required'
      });
    }
    
    const normalizedPhone = normalizePhone(phone);
    
    // Validate phone number format
    if (normalizedPhone.length < 10 || !/^\+?\d{10,}$/.test(normalizedPhone)) {
      return res.status(400).json({
        success: false,
        error: 'invalid_phone',
        message: 'Invalid phone number format'
      });
    }
    
    // Find or create user
    let user = await User.findOne({ phone: normalizedPhone });
    
    if (user) {
      // Update name if provided and different
      if (name && name.trim() && user.name !== name.trim()) {
        await User.findByIdAndUpdate(user._id, { name: name.trim() });
        user.name = name.trim();
      }
    } else {
      // Create new user if doesn't exist
      const userName = (name && name.trim()) || normalizedPhone;
      user = await User.create({
        name: userName,
        phone: normalizedPhone
      });
    }
    
    // Generate OTP and session ID
    const otp = generateOTP();
    const sessionId = crypto.randomBytes(16).toString('hex');
    const expiresAt = new Date(Date.now() + config.otpExpiryMinutes * 60 * 1000);
    
    // Store OTP in database
    await Otp.create({
      phone: normalizedPhone,
      otp,
      sessionId,
      userId: user._id,
      expiresAt,
      isLogin: true
    });
    
    // Log OTP for development
    if (config.nodeEnv !== 'production') {
      console.log('═══════════════════════════════════════════════════');
      console.log('📱 LOGIN OTP GENERATED');
      console.log('═══════════════════════════════════════════════════');
      console.log('User:', user.name);
      console.log('Phone Number:', normalizedPhone);
      console.log('Session ID:', sessionId);
      console.log('OTP Code:', otp);
      console.log('Expires At:', expiresAt.toISOString());
      console.log('═══════════════════════════════════════════════════');
    }
    
    res.status(200).json({
      success: true,
      sessionId,
      message: 'OTP sent successfully',
      ...(config.nodeEnv !== 'production' && { otp }) // Only return OTP in dev
    });
  } catch (error) {
    console.error('❌ Send OTP Login error:', error);
    
    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        error: 'phone_taken',
        message: 'Phone number is already registered'
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Internal server error'
    });
  }
};

/**
 * Verify OTP for login
 */
export const verifyOtpLogin = async (req, res) => {
  try {
    const { otp, sessionId } = req.body;
    
    if (!otp || !sessionId) {
      return res.status(400).json({
        success: false,
        error: 'missing',
        message: 'OTP and sessionId are required'
      });
    }
    
    // Validate OTP format
    if (!/^\d{6}$/.test(otp)) {
      return res.status(400).json({
        success: false,
        error: 'invalid_otp_format',
        message: 'OTP must be 6 digits'
      });
    }
    
    // Get stored OTP from database
    const storedOtp = await Otp.findOne({
      sessionId,
      isLogin: true,
      used: false,
      expiresAt: { $gt: new Date() }
    });
    
    if (!storedOtp) {
      return res.status(400).json({
        success: false,
        error: 'invalid_otp',
        message: 'Invalid or expired OTP'
      });
    }
    
    // Verify OTP code
    if (storedOtp.otp !== otp) {
      return res.status(400).json({
        success: false,
        error: 'invalid_otp',
        message: 'Invalid OTP code'
      });
    }
    
    // Get user
    const user = await User.findById(storedOtp.userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'user_not_found',
        message: 'User not found'
      });
    }
    
    // Mark OTP as used
    await Otp.findByIdAndUpdate(storedOtp._id, { used: true });
    
    // Update user online status
    user.isOnline = true;
    user.lastSeen = new Date();
    await user.save();
    
    // Create session
    const sessionIdForToken = uuidv4();
    const deviceInfo = {
      device: req.get('X-Device-Name') || req.get('User-Agent')?.split(' ')[0] || 'Unknown',
      ip: req.ip || req.connection.remoteAddress || 'Unknown',
      userAgent: req.get('User-Agent') || 'Unknown'
    };
    
    // Generate JWT token
    const token = signToken(user._id, sessionIdForToken, deviceInfo);
    
    // Create session record
    await Session.create({
      userId: user._id,
      sessionId: sessionIdForToken,
      device: deviceInfo.device,
      ip: deviceInfo.ip,
      token,
      userAgent: deviceInfo.userAgent,
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      valid: true
    });
    
    res.status(200).json({
      success: true,
      token,
      sessionId: sessionIdForToken,
      user: {
        id: String(user._id),
        uid: String(user._id),
        userId: String(user._id),
        name: user.name,
        phone: user.phone,
        avatar: user.avatar || user.avatarUrl || null,
        avatarUrl: user.avatarUrl || user.avatar || null,
        bio: user.bio || null,
        isOnline: user.isOnline,
        lastSeen: user.lastSeen
      }
    });
  } catch (error) {
    console.error('❌ Verify OTP Login error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Internal server error'
    });
  }
};

/**
 * Password login
 */
export const login = async (req, res) => {
  try {
    const { name, password } = req.body;
    
    if (!name || !password) {
      return res.status(400).json({
        success: false,
        error: 'missing',
        message: 'Name/phone and password are required'
      });
    }
    
    const identifier = name.toString().trim();
    const normalizedPhone = normalizePhone(identifier);
    
    // Find user by name or phone
    const user = await User.findOne({
      $or: [
        { name: identifier },
        { phone: normalizedPhone }
      ]
    });
    
    if (!user || !user.passwordHash) {
      return res.status(401).json({
        success: false,
        error: 'invalid_credentials',
        message: 'Invalid credentials'
      });
    }
    
    // Verify password
    const isValid = await bcrypt.compare(password.toString(), user.passwordHash);
    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'invalid_credentials',
        message: 'Invalid credentials'
      });
    }
    
    // Update online status
    user.isOnline = true;
    user.lastSeen = new Date();
    await user.save();
    
    // Generate token (simple format - Backend1 style)
    const token = signToken(user._id);
    
    res.status(200).json({
      success: true,
      token,
      user: {
        id: String(user._id),
        uid: String(user._id),
        userId: String(user._id),
        name: user.name,
        phone: user.phone || null,
        avatar: user.avatar || user.avatarUrl || null,
        avatarUrl: user.avatarUrl || user.avatar || null,
        bio: user.bio || null,
        isOnline: user.isOnline,
        lastSeen: user.lastSeen
      }
    });
  } catch (error) {
    console.error('❌ Login error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Internal server error'
    });
  }
};

/**
 * Get current user
 */
export const getMe = async (req, res) => {
  try {
    const userId = req.user.id || req.user.uid || req.user.userId;
    const user = await User.findById(userId).select('-password -passwordHash').lean();
    
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'user_not_found',
        message: 'User not found'
      });
    }
    
    res.json({
      success: true,
      user: {
        id: String(user._id),
        uid: String(user._id),
        userId: String(user._id),
        name: user.name,
        phone: user.phone || null,
        avatar: user.avatar || user.avatarUrl || null,
        avatarUrl: user.avatarUrl || user.avatar || null,
        bio: user.bio || null,
        isOnline: user.isOnline,
        lastSeen: user.lastSeen
      }
    });
  } catch (error) {
    console.error('❌ Get me error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Internal server error'
    });
  }
};

// Export default object for route compatibility
export default {
  sendOtp,
  verifyOtpRegister,
  sendOtpLogin,
  verifyOtpLogin,
  login,
  getMe
};

