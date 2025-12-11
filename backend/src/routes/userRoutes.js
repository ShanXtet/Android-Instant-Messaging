import express from 'express';
import userController from '../controllers/userController.js';
import { requireAuth } from '../middlewares/authMiddleware.js';
import { apiLimiter } from '../middlewares/rateLimiter.js';

const router = express.Router();

// Apply authentication and rate limiting
router.use(requireAuth);
router.use(apiLimiter);

// Search users (must be before '/' route)
router.get('/search', userController.searchUsers);

// Get users by IDs (Backend1 style - must be before '/' route)
router.get('/by-ids', userController.getUsersByIds);

// Presence (Backend1 style)
router.get('/presence', requireAuth, userController.getPresence);

// Get all users
router.get('/', userController.getUsers);

// Get current user profile
router.get('/profile', userController.getCurrentUserProfile);

// Update current user profile
router.patch('/me', userController.updateProfile);
router.put('/me', userController.updateProfile);

// Get user profile by ID (must be last due to :userId parameter)
router.get('/profile/:userId', userController.getUserProfile);

// Get online users count
router.get('/online/count', userController.getOnlineUsersCount);

export default router;

