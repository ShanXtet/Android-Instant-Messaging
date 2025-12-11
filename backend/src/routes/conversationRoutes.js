import express from 'express';
import conversationController from '../controllers/conversationController.js';
import { requireAuth } from '../middlewares/authMiddleware.js';
import { apiLimiter } from '../middlewares/rateLimiter.js';

const router = express.Router();

// Apply authentication and rate limiting
router.use(requireAuth);
router.use(apiLimiter);

// Chat requests (Backend1 style - must be before other routes)
router.post('/chat-requests', conversationController.sendChatRequest);
router.get('/chat-requests', conversationController.getChatRequests);
router.post('/chat-requests/:id/accept', conversationController.acceptChatRequest);
router.post('/chat-requests/:id/decline', conversationController.declineChatRequest);

// Contact sync (Backend1 style)
router.post('/contacts/sync', conversationController.syncContacts);
router.post('/contacts/start-chat', conversationController.startChat);

// Get conversations
router.get('/', conversationController.getConversations);

// Create conversation
router.post('/', conversationController.createConversation);

// Get conversation details (must be last due to :conversationId parameter)
router.get('/:conversationId', conversationController.getConversationDetails);

// Delete/hide conversation
router.delete('/:conversationId', conversationController.deleteConversation);

export default router;

