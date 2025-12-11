import rateLimit from 'express-rate-limit';
import config from '../config/index.js';

/**
 * General API rate limiter
 */
export const apiLimiter = rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.max,
  message: {
    error: 'too_many_requests',
    message: 'Too many requests from this IP, please try again later.'
  },
  standardHeaders: true, // Send standard rate limit headers
  legacyHeaders: false, // Disable X-RateLimit-* headers
});

/**
 * Stricter rate limiter for authentication endpoints
 */
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 requests per window
  message: {
    error: 'too_many_requests',
    message: 'Too many authentication attempts, please try again later.'
  },
  skipSuccessfulRequests: true, // Don't count successful requests
  standardHeaders: true,
  legacyHeaders: false,
});

/**
 * Rate limiter for OTP endpoints
 */
export const otpLimiter = rateLimit({
  windowMs: 5 * 60 * 1000, // 5 minutes
  max: 3, // 3 OTP requests per 5 minutes
  message: {
    error: 'too_many_otp_requests',
    message: 'Too many OTP requests, please try again later.'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

/**
 * Rate limiter for message sending
 */
export const messageLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 30, // 30 messages per minute
  message: {
    error: 'too_many_messages',
    message: 'Message sending rate exceeded, please slow down.'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

