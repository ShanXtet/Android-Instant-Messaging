import notificationService from '../services/notificationService.js';

/**
 * Get user notifications
 */
export const getNotifications = async (req, res) => {
  try {
    const userId = req.user.id || req.user.uid || req.user.userId;
    const { page = 1, limit = 20, type } = req.query;

    const result = await notificationService.getUserNotifications(userId, {
      page: parseInt(page),
      limit: parseInt(limit),
      type
    });

    res.json({
      success: true,
      ...result
    });
  } catch (error) {
    console.error('❌ Get notifications error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error fetching notifications'
    });
  }
};

/**
 * Mark notification as read
 */
export const markAsRead = async (req, res) => {
  try {
    const { notificationId } = req.params;
    const userId = req.user.id || req.user.uid || req.user.userId;

    const notification = await notificationService.markAsRead(notificationId, userId);

    if (!notification) {
      return res.status(404).json({
        success: false,
        error: 'not_found',
        message: 'Notification not found'
      });
    }

    res.json({
      success: true,
      notification
    });
  } catch (error) {
    console.error('❌ Mark notification as read error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error marking notification as read'
    });
  }
};

/**
 * Mark all notifications as read
 */
export const markAllAsRead = async (req, res) => {
  try {
    const userId = req.user.id || req.user.uid || req.user.userId;

    const count = await notificationService.markAllAsRead(userId);

    res.json({
      success: true,
      count
    });
  } catch (error) {
    console.error('❌ Mark all notifications as read error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error marking all notifications as read'
    });
  }
};

/**
 * Get unread count
 */
export const getUnreadCount = async (req, res) => {
  try {
    const userId = req.user.id || req.user.uid || req.user.userId;

    const count = await notificationService.getUnreadCount(userId);

    res.json({
      success: true,
      count
    });
  } catch (error) {
    console.error('❌ Get unread count error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error getting unread count'
    });
  }
};

// Export default object for route compatibility
export default {
  getNotifications,
  markAsRead,
  markAllAsRead,
  getUnreadCount
};

