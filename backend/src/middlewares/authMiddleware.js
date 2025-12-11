import jwt from 'jsonwebtoken';
import config from '../config/index.js';
import Session from '../models/Session.js';
import User from '../models/User.js';

/**
 * Standard JWT authentication middleware
 * Supports both uid (Backend1) and id/userId (Backend) in JWT
 */
export const requireAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ 
        success: false,
        error: 'unauthorized',
        message: 'Access token required. Please provide Authorization: Bearer <token>' 
      });
    }

    const token = authHeader.substring(7); // Remove 'Bearer ' prefix

    // Verify JWT token
    let decoded;
    try {
      decoded = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256', 'HS512'] });
    } catch (jwtError) {
      console.log('❌ JWT verification failed:', jwtError.message);
      return res.status(401).json({
        success: false,
        error: 'invalid_token',
        message: 'Invalid or expired token'
      });
    }

    // Extract user ID (support multiple formats)
    const userId = decoded.uid || decoded.id || decoded.userId || decoded._id;
    
    if (!userId) {
      return res.status(401).json({
        success: false,
        error: 'invalid_token',
        message: 'Token does not contain user ID'
      });
    }

    // Get user from database
    const user = await User.findById(userId).select('-password -passwordHash').lean();
    if (!user) {
      return res.status(401).json({
        success: false,
        error: 'user_not_found',
        message: 'User not found'
      });
    }

    // Attach user info to request (unified format)
    req.user = {
      id: String(user._id),
      uid: String(user._id), // Backend1 compatibility
      userId: String(user._id), // Backend compatibility
      _id: user._id,
      phone: user.phone,
      name: user.name,
      ...user
    };

    // Attach session info if available
    if (decoded.sessionId) {
      req.user.sessionId = decoded.sessionId;
    }
    if (decoded.device) {
      req.user.device = decoded.device;
    }
    if (decoded.ip) {
      req.user.ip = decoded.ip;
    }

    next();
  } catch (error) {
    console.error('❌ Auth middleware error:', error);
    return res.status(500).json({
      success: false,
      error: 'server_error',
      message: 'Authentication error'
    });
  }
};

/**
 * Session-based authentication middleware (Backend style)
 * Validates JWT token and checks session validity in database
 */
export const requireSessionAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        error: 'unauthorized',
        message: 'Access token required'
      });
    }

    const token = authHeader.substring(7);

    // Verify JWT token
    let decoded;
    try {
      decoded = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256', 'HS512'] });
    } catch (jwtError) {
      return res.status(401).json({
        success: false,
        error: 'invalid_token',
        message: 'Invalid or expired token'
      });
    }

    // Extract user ID
    const userId = decoded.uid || decoded.id || decoded.userId || decoded._id;
    const sessionId = decoded.sessionId;

    if (!userId || !sessionId) {
      return res.status(401).json({
        success: false,
        error: 'invalid_token',
        message: 'Token missing required fields'
      });
    }

    // Check if session exists and is valid in database
    const session = await Session.findOne({
      sessionId: sessionId,
      userId: userId,
      token: token,
      valid: true,
      expiresAt: { $gt: new Date() }
    });

    if (!session) {
      return res.status(401).json({
        success: false,
        error: 'invalid_session',
        message: 'Session not found or expired'
      });
    }

    // Update last activity
    await session.updateActivity();

    // Get user information
    const user = await User.findById(userId).select('-password -passwordHash').lean();
    if (!user) {
      return res.status(401).json({
        success: false,
        error: 'user_not_found',
        message: 'User not found'
      });
    }

    // Attach user and session info to request
    req.user = {
      id: String(user._id),
      uid: String(user._id),
      userId: String(user._id),
      _id: user._id,
      sessionId: sessionId,
      device: decoded.device,
      ip: decoded.ip,
      ...user
    };
    req.session = session;

    next();
  } catch (error) {
    console.error('❌ Session auth middleware error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: 'Authentication error'
    });
  }
};

/**
 * Optional authentication middleware
 * Doesn't fail if no token provided
 */
export const optionalAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      req.user = null;
      return next();
    }

    // Use standard auth middleware
    return requireAuth(req, res, next);
  } catch (error) {
    req.user = null;
    next();
  }
};

