import express from 'express';
import authController from '../controllers/authController.js';
import { authLimiter, otpLimiter } from '../middlewares/rateLimiter.js';
import { requireAuth } from '../middlewares/authMiddleware.js';

const router = express.Router();

// OTP endpoints with rate limiting
router.post('/send-otp', otpLimiter, authController.sendOtp);
router.post('/verify-otp-register', authLimiter, authController.verifyOtpRegister);
router.post('/send-otp-login', otpLimiter, authController.sendOtpLogin);
router.post('/verify-otp-login', authLimiter, authController.verifyOtpLogin);

// Password login
router.post('/login', authLimiter, authController.login);

// Get current user (requires auth)
router.get('/me', requireAuth, authController.getMe);

export default router;

