import Group from '../models/Group.js';
import Conversation from '../models/Conversation.js';
import Message from '../models/Message.js';
import User from '../models/User.js';
import crypto from 'crypto';

/**
 * Group Service
 * Handles all group-related business logic
 */
class GroupService {
  /**
   * Create a new group with associated conversation
   */
  async createGroup(data) {
    const { name, description, adminId, participantIds = [], avatar } = data;
    
    // Ensure admin is in participants
    const allParticipants = [...new Set([adminId, ...participantIds])];
    
    // Create group
    const group = await Group.create({
      name,
      description,
      admin: adminId,
      admins: [adminId],
      participants: allParticipants,
      avatar
    });
    
    // Create associated conversation
    const conversation = await Conversation.create({
      participants: allParticipants,
      members: allParticipants,
      isGroup: true,
      status: 'active',
      createdBy: adminId,
      lastMessageAt: null
    });
    
    // Link conversation to group
    group.conversation = conversation._id;
    group.conversationId = conversation._id;
    await group.save();
    
    // Populate group details
    await group.populate([
      { path: 'admin', select: 'name phone avatar avatarUrl' },
      { path: 'participants', select: 'name phone avatar avatarUrl isOnline lastSeen' }
    ]);
    
    return { group, conversation };
  }
  
  /**
   * Get group details
   */
  async getGroupDetails(groupId, userId) {
    const group = await Group.findById(groupId)
      .populate('admin', 'name phone avatar avatarUrl')
      .populate('admins', 'name phone avatar avatarUrl')
      .populate('participants', 'name phone avatar avatarUrl isOnline lastSeen');
    
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check if user is a member
    if (!group.isMember(userId)) {
      throw new Error('Not a member of this group');
    }
    
    return group;
  }
  
  /**
   * Get user's groups
   */
  async getUserGroups(userId, options = {}) {
    const { page = 1, limit = 20, search } = options;
    
    const query = {
      $or: [
        { participants: userId },
        { members: userId }
      ]
    };
    
    if (search) {
      query.name = { $regex: search, $options: 'i' };
    }
    
    const groups = await Group.find(query)
      .populate('admin', 'name phone avatar avatarUrl')
      .populate('participants', 'name phone avatar avatarUrl')
      .sort({ lastActivity: -1, updatedAt: -1 })
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .lean();
    
    const total = await Group.countDocuments(query);
    
    return {
      groups,
      pagination: {
        totalPages: Math.ceil(total / limit),
        currentPage: page,
        total,
        limit
      }
    };
  }
  
  /**
   * Add participant to group
   */
  async addParticipant(groupId, userId, addedBy) {
    const group = await Group.findById(groupId);
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check permissions
    if (group.settings.onlyAdminsCanAddMembers && !group.isAdmin(addedBy)) {
      throw new Error('Only admins can add members');
    }
    
    // Check if user is already a member
    if (group.isMember(userId)) {
      throw new Error('User is already a member');
    }
    
    // Add member
    await group.addMember(userId);
    
    // Add to associated conversation
    if (group.conversation) {
      const conversation = await Conversation.findById(group.conversation);
      if (conversation) {
        if (!conversation.participants.includes(userId)) {
          conversation.participants.push(userId);
          if (conversation.members) {
            conversation.members.push(userId);
          }
          await conversation.save();
        }
      }
    }
    
    // Populate and return
    await group.populate([
      { path: 'admin', select: 'name phone avatar avatarUrl' },
      { path: 'participants', select: 'name phone avatar avatarUrl' }
    ]);
    
    return group;
  }
  
  /**
   * Remove participant from group
   */
  async removeParticipant(groupId, userId, removedBy) {
    const group = await Group.findById(groupId);
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check if user is admin
    if (group.isAdmin(userId)) {
      throw new Error('Cannot remove admin from group');
    }
    
    // Check permissions
    if (!group.isAdmin(removedBy) && removedBy.toString() !== userId.toString()) {
      throw new Error('Only admins can remove other members');
    }
    
    // Remove member
    await group.removeMember(userId);
    
    // Remove from associated conversation
    if (group.conversation) {
      const conversation = await Conversation.findById(group.conversation);
      if (conversation) {
        conversation.participants = conversation.participants.filter(
          p => p.toString() !== userId.toString()
        );
        if (conversation.members) {
          conversation.members = conversation.members.filter(
            m => m.toString() !== userId.toString()
          );
        }
        await conversation.save();
      }
    }
    
    // Populate and return
    await group.populate([
      { path: 'admin', select: 'name phone avatar avatarUrl' },
      { path: 'participants', select: 'name phone avatar avatarUrl' }
    ]);
    
    return group;
  }
  
  /**
   * Update group details
   */
  async updateGroup(groupId, updates, userId) {
    const group = await Group.findById(groupId);
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check if user is admin
    if (!group.isAdmin(userId)) {
      throw new Error('Only admins can update group');
    }
    
    // Update allowed fields
    const allowedUpdates = ['name', 'description', 'avatar', 'avatarUrl', 'settings'];
    const updateData = {};
    
    for (const field of allowedUpdates) {
      if (updates[field] !== undefined) {
        updateData[field] = updates[field];
      }
    }
    
    // Sync avatar fields
    if (updateData.avatar && !updateData.avatarUrl) {
      updateData.avatarUrl = updateData.avatar;
    }
    if (updateData.avatarUrl && !updateData.avatar) {
      updateData.avatar = updateData.avatarUrl;
    }
    
    const updatedGroup = await Group.findByIdAndUpdate(
      groupId,
      updateData,
      { new: true, runValidators: true }
    ).populate([
      { path: 'admin', select: 'name phone avatar avatarUrl' },
      { path: 'participants', select: 'name phone avatar avatarUrl' }
    ]);
    
    return updatedGroup;
  }
  
  /**
   * Leave group
   */
  async leaveGroup(groupId, userId) {
    const group = await Group.findById(groupId);
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check if user is a member
    if (!group.isMember(userId)) {
      throw new Error('Not a member of this group');
    }
    
    // Cannot leave if you're the only admin
    if (group.isAdmin(userId) && group.admins.length === 1 && group.participants.length > 1) {
      throw new Error('Cannot leave group as the only admin. Transfer admin role first or add another admin.');
    }
    
    // Remove from admins if admin
    if (group.isAdmin(userId)) {
      group.admins = group.admins.filter(a => a.toString() !== userId.toString());
      // Transfer admin to first participant if no admins left
      if (group.admins.length === 0 && group.participants.length > 1) {
        const newAdmin = group.participants.find(p => p.toString() !== userId.toString());
        if (newAdmin) {
          group.admin = newAdmin;
          group.admins = [newAdmin];
        }
      }
    }
    
    // Remove member
    await group.removeMember(userId);
    
    // Remove from associated conversation
    if (group.conversation) {
      const conversation = await Conversation.findById(group.conversation);
      if (conversation) {
        conversation.participants = conversation.participants.filter(
          p => p.toString() !== userId.toString()
        );
        if (conversation.members) {
          conversation.members = conversation.members.filter(
            m => m.toString() !== userId.toString()
          );
        }
        await conversation.save();
      }
    }
    
    return group;
  }
  
  /**
   * Promote member to admin
   */
  async promoteToAdmin(groupId, userId, promotedBy) {
    const group = await Group.findById(groupId);
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check if promoter is admin
    if (!group.isAdmin(promotedBy)) {
      throw new Error('Only admins can promote members');
    }
    
    // Check if user is a member
    if (!group.isMember(userId)) {
      throw new Error('User is not a member of this group');
    }
    
    // Check if already admin
    if (group.isAdmin(userId)) {
      throw new Error('User is already an admin');
    }
    
    // Add to admins array
    if (!group.admins) {
      group.admins = [];
    }
    group.admins.push(userId);
    await group.save();
    
    await group.populate([
      { path: 'admin', select: 'name phone avatar avatarUrl' },
      { path: 'admins', select: 'name phone avatar avatarUrl' },
      { path: 'participants', select: 'name phone avatar avatarUrl' }
    ]);
    
    return group;
  }
  
  /**
   * Demote admin to member
   */
  async demoteAdmin(groupId, userId, demotedBy) {
    const group = await Group.findById(groupId);
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check if demoter is admin
    if (!group.isAdmin(demotedBy)) {
      throw new Error('Only admins can demote other admins');
    }
    
    // Cannot demote main admin
    if (group.admin.toString() === userId.toString()) {
      throw new Error('Cannot demote main admin');
    }
    
    // Check if user is admin
    if (!group.isAdmin(userId)) {
      throw new Error('User is not an admin');
    }
    
    // Remove from admins array
    group.admins = group.admins.filter(a => a.toString() !== userId.toString());
    await group.save();
    
    await group.populate([
      { path: 'admin', select: 'name phone avatar avatarUrl' },
      { path: 'admins', select: 'name phone avatar avatarUrl' },
      { path: 'participants', select: 'name phone avatar avatarUrl' }
    ]);
    
    return group;
  }
  
  /**
   * Generate invite link
   */
  async generateInviteLink(groupId, userId) {
    const group = await Group.findById(groupId);
    if (!group) {
      throw new Error('Group not found');
    }
    
    // Check if user is admin
    if (!group.isAdmin(userId)) {
      throw new Error('Only admins can generate invite links');
    }
    
    const inviteLink = Group.generateInviteLink();
    
    group.settings.inviteLink = inviteLink;
    await group.save();
    
    return inviteLink;
  }
  
  /**
   * Join group via invite link
   */
  async joinViaInviteLink(inviteLink, userId) {
    const group = await Group.findOne({ 'settings.inviteLink': inviteLink });
    if (!group) {
      throw new Error('Invalid invite link');
    }
    
    // Check if user is already a member
    if (group.isMember(userId)) {
      return group;
    }
    
    // Add user to group
    await this.addParticipant(group._id, userId, group.admin);
    
    await group.populate([
      { path: 'admin', select: 'name phone avatar avatarUrl' },
      { path: 'participants', select: 'name phone avatar avatarUrl' }
    ]);
    
    return group;
  }
  
  /**
   * Search groups
   */
  async searchGroups(userId, searchQuery, options = {}) {
    const { limit = 20 } = options;
    
    const query = {
      $or: [
        { participants: userId },
        { members: userId }
      ],
      name: { $regex: searchQuery, $options: 'i' }
    };
    
    const groups = await Group.find(query)
      .populate('admin', 'name phone avatar avatarUrl')
      .populate('participants', 'name phone avatar avatarUrl')
      .sort({ lastActivity: -1 })
      .limit(limit)
      .lean();
    
    return groups;
  }
}

export default GroupService;

