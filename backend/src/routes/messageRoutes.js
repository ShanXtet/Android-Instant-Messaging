import express from 'express';
import messageController from '../controllers/messageController.js';
import { requireAuth } from '../middlewares/authMiddleware.js';
import { messageLimiter, apiLimiter } from '../middlewares/rateLimiter.js';
import { upload, voiceUpload } from '../middlewares/uploadMiddleware.js';

const router = express.Router();

// Apply authentication and rate limiting
router.use(requireAuth);
router.use(apiLimiter);

// Upload endpoints (before other routes)
router.post('/upload', upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'no_file',
        message: 'No file uploaded'
      });
    }

    const protocol = req.protocol || 'http';
    const host = req.get('host') || 'localhost:3000';
    const fileUrl = `${protocol}://${host}/uploads/${req.file.filename}`;

    res.json({
      success: true,
      url: fileUrl,
      fileUrl,
      fileName: req.file.filename,
      originalName: req.file.originalname,
      size: req.file.size,
      mimetype: req.file.mimetype
    });
  } catch (error) {
    console.error('❌ File upload error:', error);
    res.status(500).json({
      success: false,
      error: 'server_error',
      message: error.message || 'Error uploading file'
    });
  }
});

// Voice message upload
router.post('/voice', messageLimiter, voiceUpload.single('voice'), messageController.uploadVoiceMessage);

// Search messages (must be before :id route)
router.get('/search', messageController.searchMessages);

// Send message
router.post('/', messageLimiter, messageController.sendMessage);

// Edit message
router.patch('/:id', messageController.editMessage);

// Delete message
router.delete('/:id', messageController.deleteMessage);

// Mark message as read
router.patch('/:id/read', messageController.markAsRead);

// Get messages - supports both /:conversationId and query params
router.get('/conversation/:conversationId', messageController.getMessages);
router.get('/', messageController.getMessages); // For query params style

export default router;

