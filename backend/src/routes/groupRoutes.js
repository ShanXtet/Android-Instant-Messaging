import express from 'express';
import groupController from '../controllers/groupController.js';
import { requireAuth } from '../middlewares/authMiddleware.js';
import { apiLimiter } from '../middlewares/rateLimiter.js';

const router = express.Router();

// Apply authentication and rate limiting to all routes
router.use(requireAuth);
router.use(apiLimiter);

// Search groups (MUST be before '/:groupId' route)
router.get('/search', groupController.searchGroups);

// Create a new group
router.post('/create', groupController.createGroup);
router.post('/', groupController.createGroup); // Alternative route

// Get user's groups
router.get('/', groupController.getUserGroups);

// Join group via invite link
router.post('/join', groupController.joinViaInviteLink);

// Generate invite link (specific route before :groupId)
router.get('/:groupId/invite-link', groupController.generateInviteLink);

// Leave group
router.delete('/:groupId/leave', groupController.leaveGroup);

// Promote to admin
router.post('/promote-admin', groupController.promoteToAdmin);

// Demote admin
router.post('/demote-admin', groupController.demoteAdmin);

// Update group details
router.put('/:groupId', groupController.updateGroup);
router.patch('/:groupId', groupController.updateGroup); // Alternative method

// Add participant
router.post('/add-participant', groupController.addParticipant);

// Remove participant
router.post('/remove-participant', groupController.removeParticipant);

// Get group details (must be last due to :groupId parameter)
router.get('/:groupId', groupController.getGroupDetails);

export default router;

