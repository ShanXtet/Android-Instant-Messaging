import User from '../models/User.js';

/**
 * Get all users (with search and pagination)
 */
export const getUsers = async (req, res) => {
  try {
    const { search, page = 1, limit = 20 } = req.query;
    const userId = req.user.id || req.user.uid || req.user.userId;

    let query = { _id: { $ne: userId } };

    if (search) {
      query.$or = [
        { name: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } }
      ];
    }

    const users = await User.find(query)
      .select('-password -passwordHash')
      .limit(parseInt(limit))
      .skip((parseInt(page) - 1) * parseInt(limit))
      .sort({ name: 1 })
      .lean();

    const total = await User.countDocuments(query);

    const formatted = users.map(u => ({
      _id: String(u._id),
      id: String(u._id),
      name: u.name,
      phone: u.phone || null,
      avatar: u.avatar || u.avatarUrl || null,
      avatarUrl: u.avatarUrl || u.avatar || null,
      bio: u.bio || null,
      isOnline: u.isOnline || false,
      lastSeen: u.lastSeen
    }));

    res.json({
      success: true,
      users: formatted,
      pagination: {
        totalPages: Math.ceil(total / limit),
        currentPage: parseInt(page),
        total,
        limit: parseInt(limit)
      }
    });
  } catch (error) {
    console.error('❌ Get users error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching users'
    });
  }
};

/**
 * Search users
 */
export const searchUsers = async (req, res) => {
  try {
    const { q: searchQuery } = req.query;
    const userId = req.user.id || req.user.uid || req.user.userId;

    if (!searchQuery || searchQuery.trim().length < 2) {
      return res.json({
        success: true,
        users: []
      });
    }

    const query = {
      _id: { $ne: userId },
      $or: [
        { name: { $regex: searchQuery, $options: 'i' } },
        { phone: { $regex: searchQuery, $options: 'i' } }
      ]
    };

    const users = await User.find(query)
      .select('-password -passwordHash')
      .limit(20)
      .sort({ name: 1 })
      .lean();

    const formatted = users.map(u => ({
      _id: String(u._id),
      id: String(u._id),
      name: u.name,
      phone: u.phone || null,
      avatar: u.avatar || u.avatarUrl || null,
      avatarUrl: u.avatarUrl || u.avatar || null,
      bio: u.bio || null,
      isOnline: u.isOnline || false,
      lastSeen: u.lastSeen
    }));

    res.json({
      success: true,
      users: formatted
    });
  } catch (error) {
    console.error('❌ Search users error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error searching users'
    });
  }
};

/**
 * Get current user profile
 */
export const getCurrentUserProfile = async (req, res) => {
  try {
    const userId = req.user.id || req.user.uid || req.user.userId;
    const user = await User.findById(userId).select('-password -passwordHash').lean();

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: 'User not found'
      });
    }

    res.json({
      success: true,
      user: {
        _id: String(user._id),
        id: String(user._id),
        uid: String(user._id),
        userId: String(user._id),
        name: user.name,
        phone: user.phone || null,
        avatar: user.avatar || user.avatarUrl || null,
        avatarUrl: user.avatarUrl || user.avatar || null,
        bio: user.bio || null,
        isOnline: user.isOnline || false,
        lastSeen: user.lastSeen
      }
    });
  } catch (error) {
    console.error('❌ Get current user profile error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching user profile'
    });
  }
};

/**
 * Get user profile by ID
 */
export const getUserProfile = async (req, res) => {
  try {
    const { userId } = req.params;
    const user = await User.findById(userId).select('-password -passwordHash').lean();

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: 'User not found'
      });
    }

    res.json({
      success: true,
      user: {
        _id: String(user._id),
        id: String(user._id),
        name: user.name,
        phone: user.phone || null,
        avatar: user.avatar || user.avatarUrl || null,
        avatarUrl: user.avatarUrl || user.avatar || null,
        bio: user.bio || null,
        isOnline: user.isOnline || false,
        lastSeen: user.lastSeen
      }
    });
  } catch (error) {
    console.error('❌ Get user profile error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching user profile'
    });
  }
};

/**
 * Update user profile
 */
export const updateProfile = async (req, res) => {
  try {
    const { name, avatar, avatarUrl, bio, dateOfBirth, username } = req.body;
    const userId = req.user.id || req.user.uid || req.user.userId;

    const updateData = {};
    if (name !== undefined) updateData.name = name.trim();
    if (bio !== undefined) updateData.bio = bio?.trim() || null;
    if (dateOfBirth !== undefined) updateData.dateOfBirth = dateOfBirth;
    if (username !== undefined) updateData.username = username?.trim() || null;

    // Handle avatar (support both field names)
    if (avatar !== undefined) {
      updateData.avatar = avatar?.trim() || null;
      if (!avatarUrl) updateData.avatarUrl = avatar?.trim() || null;
    }
    if (avatarUrl !== undefined) {
      updateData.avatarUrl = avatarUrl?.trim() || null;
      if (!avatar) updateData.avatar = avatarUrl?.trim() || null;
    }

    const updatedUser = await User.findByIdAndUpdate(
      userId,
      updateData,
      { new: true, runValidators: true }
    ).select('-password -passwordHash').lean();

    if (!updatedUser) {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: 'User not found'
      });
    }

    // Broadcast profile update
    const io = req.app.get('io');
    if (io) {
      io.emit('user_profile_updated', {
        userId: String(updatedUser._id),
        user: {
          id: String(updatedUser._id),
          name: updatedUser.name,
          phone: updatedUser.phone || null,
          avatar: updatedUser.avatar || updatedUser.avatarUrl || null,
          avatarUrl: updatedUser.avatarUrl || updatedUser.avatar || null,
          bio: updatedUser.bio || null
        }
      });
    }

    res.json({
      success: true,
      user: {
        _id: String(updatedUser._id),
        id: String(updatedUser._id),
        uid: String(updatedUser._id),
        userId: String(updatedUser._id),
        name: updatedUser.name,
        phone: updatedUser.phone || null,
        avatar: updatedUser.avatar || updatedUser.avatarUrl || null,
        avatarUrl: updatedUser.avatarUrl || updatedUser.avatar || null,
        bio: updatedUser.bio || null,
        isOnline: updatedUser.isOnline || false,
        lastSeen: updatedUser.lastSeen
      }
    });
  } catch (error) {
    console.error('❌ Update profile error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error updating profile'
    });
  }
};

/**
 * Get users by IDs (Backend1 style)
 */
export const getUsersByIds = async (req, res) => {
  try {
    const idsRaw = (req.query.ids || '').toString();
    
    // Clean and validate IDs - handle malformed IDs
    const ids = idsRaw
      .split(',')
      .map(id => {
        // Remove any whitespace
        let cleanId = id.trim();
        
        // If ID looks like it contains object notation, extract just the ID
        // Handle cases like "{_id: 6938f4af986360f5d930ec09" or "{id: ...}"
        if (cleanId.includes('_id:') || cleanId.includes('id:')) {
          // Extract the ID part after the colon
          const match = cleanId.match(/[:\s]+([a-f0-9]{24})/i);
          if (match && match[1]) {
            cleanId = match[1];
          }
        }
        
        // Remove any remaining non-hex characters (keep only 0-9, a-f, A-F)
        cleanId = cleanId.replace(/[^a-f0-9]/gi, '');
        
        // Validate it's a valid MongoDB ObjectId (24 hex characters)
        if (cleanId.length === 24 && /^[a-f0-9]{24}$/i.test(cleanId)) {
          return cleanId;
        }
        
        return null;
      })
      .filter(Boolean);
    
    if (ids.length === 0) {
      return res.json({
        success: true,
        users: {}
      });
    }

    // Convert to ObjectIds for MongoDB query
    const mongoose = (await import('mongoose')).default;
    const objectIds = ids.map(id => {
      try {
        return new mongoose.Types.ObjectId(id);
      } catch (e) {
        console.warn(`⚠️ Invalid ObjectId format: ${id}`);
        return null;
      }
    }).filter(Boolean);

    if (objectIds.length === 0) {
      return res.json({
        success: true,
        users: {}
      });
    }

    const users = await User.find({ _id: { $in: objectIds } })
      .select('_id name phone avatar avatarUrl email lastSeen isOnline')
      .lean();

    const map = {};
    for (const u of users) {
      map[String(u._id)] = {
        id: String(u._id),
        name: u.name,
        phone: u.phone || null,
        email: u.email || null,
        avatar: u.avatar || u.avatarUrl || null,
        avatarUrl: u.avatarUrl || u.avatar || null,
        lastSeen: u.lastSeen ? u.lastSeen.toISOString() : null,
        isOnline: u.isOnline || false
      };
    }

    res.json({
      success: true,
      users: map
    });
  } catch (error) {
    console.error('❌ Get users by IDs error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching users'
    });
  }
};

/**
 * Get presence status (Backend1 style)
 */
export const getPresence = async (req, res) => {
  try {
    const ids = (req.query.ids || '').toString().split(',').filter(Boolean);
    const verbose = req.query.verbose === '1' || req.query.verbose === 'true';

    const presenceService = req.app.get('presenceService');

    if (ids.length === 0) {
      // Return all online users
      if (!verbose) {
        const online = presenceService ? presenceService.getOnlineUsers() : [];
        return res.json({
          success: true,
          online
        });
      } else {
        // Verbose mode - get all with status
        const users = await User.find({})
          .select('_id isOnline lastSeen')
          .lean();

        const map = {};
        for (const u of users) {
          const uid = String(u._id);
          const status = presenceService ? presenceService.getUserStatus(uid) : {};
          map[uid] = {
            online: status.online || u.isOnline || false,
            isOnline: status.isOnline || u.isOnline || false,
            at: status.at || (u.lastSeen ? u.lastSeen.toISOString() : new Date().toISOString()),
            lastSeen: u.lastSeen ? u.lastSeen.toISOString() : null
          };
        }
        return res.json({
          success: true,
          presence: map
        });
      }
    }

    // Query specific users
    if (!verbose) {
      const map = {};
      for (const id of ids) {
        if (presenceService) {
          map[id] = presenceService.isUserOnline(id);
        } else {
          const user = await User.findById(id).select('isOnline').lean();
          map[id] = user?.isOnline || false;
        }
      }
      return res.json({
        success: true,
        presence: map
      });
    } else {
      const map = {};
      for (const id of ids) {
        const status = presenceService ? presenceService.getUserStatus(id) : {};
        const user = await User.findById(id).select('isOnline lastSeen').lean();
        map[id] = {
          online: status.online || user?.isOnline || false,
          isOnline: status.isOnline || user?.isOnline || false,
          at: status.at || (user?.lastSeen ? user.lastSeen.toISOString() : new Date().toISOString()),
          lastSeen: user?.lastSeen ? user.lastSeen.toISOString() : null
        };
      }
      return res.json({
        success: true,
        presence: map
      });
    }
  } catch (error) {
    console.error('❌ Get presence error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching presence'
    });
  }
};

/**
 * Get online users count
 */
export const getOnlineUsersCount = async (req, res) => {
  try {
    const presenceService = req.app.get('presenceService');
    const count = presenceService ? presenceService.getOnlineCount() : 0;

    res.json({
      success: true,
      onlineCount: count
    });
  } catch (error) {
    console.error('❌ Get online count error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error getting online count'
    });
  }
};

// Export default object for route compatibility
export default {
  getUsers,
  searchUsers,
  getCurrentUserProfile,
  getUserProfile,
  updateProfile,
  getUsersByIds,
  getPresence,
  getOnlineUsersCount
};

