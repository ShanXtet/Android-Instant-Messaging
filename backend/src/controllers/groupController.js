import GroupService from '../services/groupService.js';

// Initialize groupService instance (will be set by main server)
let groupService = null;

export const setGroupService = (ioInstance) => {
  if (!groupService) {
    groupService = new GroupService(ioInstance);
  }
};

/**
 * Create a new group
 */
export const createGroup = async (req, res) => {
  try {
    const { name, description, participants = [], avatar } = req.body;
    const adminId = req.user.id || req.user.uid || req.user.userId;
    
    if (!name || !name.trim()) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Group name is required'
      });
    }
    
    const { group, conversation } = await groupService.createGroup({
      name: name.trim(),
      description: description?.trim(),
      adminId,
      participantIds: participants,
      avatar
    });
    
    res.status(201).json({
      success: true,
      group,
      conversation
    });
  } catch (error) {
    console.error('❌ Create group error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error creating group'
    });
  }
};

/**
 * Get group details
 */
export const getGroupDetails = async (req, res) => {
  try {
    const { groupId } = req.params;
    const userId = req.user.id || req.user.uid || req.user.userId;
    
    const group = await groupService.getGroupDetails(groupId, userId);
    
    res.json({
      success: true,
      group
    });
  } catch (error) {
    console.error('❌ Get group details error:', error);
    
    if (error.message === 'Group not found') {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: error.message
      });
    }
    
    if (error.message === 'Not a member of this group') {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: error.message
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching group details'
    });
  }
};

/**
 * Get user's groups
 */
export const getUserGroups = async (req, res) => {
  try {
    const userId = req.user.id || req.user.uid || req.user.userId;
    const { page = 1, limit = 20, search } = req.query;
    
    const result = await groupService.getUserGroups(userId, {
      page: parseInt(page),
      limit: parseInt(limit),
      search
    });
    
    res.json({
      success: true,
      groups: result.groups,
      pagination: result.pagination
    });
  } catch (error) {
    console.error('❌ Get user groups error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching groups'
    });
  }
};

/**
 * Add participant to group
 */
export const addParticipant = async (req, res) => {
  try {
    const { groupId, userId } = req.body;
    const addedBy = req.user.id || req.user.uid || req.user.userId;
    
    if (!groupId || !userId) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Group ID and User ID are required'
      });
    }
    
    const group = await groupService.addParticipant(groupId, userId, addedBy);
    
    res.json({
      success: true,
      group
    });
  } catch (error) {
    console.error('❌ Add participant error:', error);
    
    if (error.message.includes('not found') || error.message.includes('Only admins')) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: error.message
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error adding participant'
    });
  }
};

/**
 * Remove participant from group
 */
export const removeParticipant = async (req, res) => {
  try {
    const { groupId, userId } = req.body;
    const removedBy = req.user.id || req.user.uid || req.user.userId;
    
    if (!groupId || !userId) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Group ID and User ID are required'
      });
    }
    
    const group = await groupService.removeParticipant(groupId, userId, removedBy);
    
    res.json({
      success: true,
      group
    });
  } catch (error) {
    console.error('❌ Remove participant error:', error);
    
    if (error.message.includes('not found') || 
        error.message.includes('Cannot remove') ||
        error.message.includes('Only admins')) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: error.message
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error removing participant'
    });
  }
};

/**
 * Update group details
 */
export const updateGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const updates = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;
    
    const group = await groupService.updateGroup(groupId, updates, userId);
    
    res.json({
      success: true,
      group
    });
  } catch (error) {
    console.error('❌ Update group error:', error);
    
    if (error.message === 'Group not found') {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: error.message
      });
    }
    
    if (error.message.includes('Only admins')) {
      return res.status(403).json({
        success: false,
        error: 'forbidden',
        message: error.message
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error updating group'
    });
  }
};

/**
 * Leave group
 */
export const leaveGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const userId = req.user.id || req.user.uid || req.user.userId;
    
    await groupService.leaveGroup(groupId, userId);
    
    res.json({
      success: true,
      message: 'Successfully left the group'
    });
  } catch (error) {
    console.error('❌ Leave group error:', error);
    
    if (error.message === 'Group not found') {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: error.message
      });
    }
    
    if (error.message.includes('Cannot leave')) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: error.message
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error leaving group'
    });
  }
};

/**
 * Promote member to admin
 */
export const promoteToAdmin = async (req, res) => {
  try {
    const { groupId, userId } = req.body;
    const promotedBy = req.user.id || req.user.uid || req.user.userId;
    
    if (!groupId || !userId) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Group ID and User ID are required'
      });
    }
    
    const group = await groupService.promoteToAdmin(groupId, userId, promotedBy);
    
    res.json({
      success: true,
      group
    });
  } catch (error) {
    console.error('❌ Promote to admin error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error promoting member'
    });
  }
};

/**
 * Demote admin to member
 */
export const demoteAdmin = async (req, res) => {
  try {
    const { groupId, userId } = req.body;
    const demotedBy = req.user.id || req.user.uid || req.user.userId;
    
    if (!groupId || !userId) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Group ID and User ID are required'
      });
    }
    
    const group = await groupService.demoteAdmin(groupId, userId, demotedBy);
    
    res.json({
      success: true,
      group
    });
  } catch (error) {
    console.error('❌ Demote admin error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error demoting admin'
    });
  }
};

/**
 * Generate invite link
 */
export const generateInviteLink = async (req, res) => {
  try {
    const { groupId } = req.params;
    const userId = req.user.id || req.user.uid || req.user.userId;
    
    const inviteLink = await groupService.generateInviteLink(groupId, userId);
    
    res.json({
      success: true,
      inviteLink
    });
  } catch (error) {
    console.error('❌ Generate invite link error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error generating invite link'
    });
  }
};

/**
 * Join group via invite link
 */
export const joinViaInviteLink = async (req, res) => {
  try {
    const { inviteLink } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;
    
    if (!inviteLink) {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: 'Invite link is required'
      });
    }
    
    const group = await groupService.joinViaInviteLink(inviteLink, userId);
    
    res.json({
      success: true,
      group
    });
  } catch (error) {
    console.error('❌ Join via invite link error:', error);
    
    if (error.message === 'Invalid invite link') {
      return res.status(400).json({
        success: false,
        error: 'validation_error',
        message: error.message
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error joining group'
    });
  }
};

/**
 * Search groups
 */
export const searchGroups = async (req, res) => {
  try {
    const { query, limit = 20 } = req.query;
    const userId = req.user.id || req.user.uid || req.user.userId;
    
    if (!query || query.trim().length < 2) {
      return res.json({
        success: true,
        groups: []
      });
    }
    
    const groups = await groupService.searchGroups(userId, query.trim(), { limit: parseInt(limit) });
    
    res.json({
      success: true,
      groups
    });
  } catch (error) {
    console.error('❌ Search groups error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error searching groups'
    });
  }
};

// Export default object for route compatibility
export default {
  createGroup,
  getGroupDetails,
  getUserGroups,
  addParticipant,
  removeParticipant,
  updateGroup,
  leaveGroup,
  promoteToAdmin,
  demoteAdmin,
  generateInviteLink,
  joinViaInviteLink,
  searchGroups
};

