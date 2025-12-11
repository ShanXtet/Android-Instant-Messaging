import express from 'express';
import notificationController from '../controllers/notificationController.js';
import { requireAuth } from '../middlewares/authMiddleware.js';
import { apiLimiter } from '../middlewares/rateLimiter.js';

const router = express.Router();

// Apply authentication and rate limiting
router.use(requireAuth);
router.use(apiLimiter);

// Get unread count (must be before /:notificationId route)
router.get('/unread/count', notificationController.getUnreadCount);

// Mark all as read (must be before /:notificationId route)
router.patch('/read-all', notificationController.markAllAsRead);

// Get notifications
router.get('/', notificationController.getNotifications);

// Mark notification as read
router.patch('/:notificationId/read', notificationController.markAsRead);

export default router;

