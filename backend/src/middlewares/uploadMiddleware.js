import multer from 'multer';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import config from '../config/index.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Create uploads directory if it doesn't exist
const uploadDir = path.join(__dirname, '../../', config.uploadDir);
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// Create subdirectories for different file types
const voicesDir = path.join(uploadDir, 'voices');
if (!fs.existsSync(voicesDir)) {
  fs.mkdirSync(voicesDir, { recursive: true });
}

// Configure storage
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Determine destination based on file type
    const isVoice = file.fieldname === 'voice' || 
                    file.mimetype.startsWith('audio/') ||
                    file.originalname.match(/\.(m4a|mp3|ogg|wav)$/i);
    
    cb(null, isVoice ? voicesDir : uploadDir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const baseName = path.basename(file.originalname, ext).replace(/\s+/g, '_');
    const uniqueName = `${baseName}_${Date.now()}_${Math.round(Math.random() * 1E9)}${ext}`;
    cb(null, uniqueName);
  },
});

// File filter: accept images, videos, audio, and common document types
const fileFilter = (req, file, cb) => {
  const allowed = [
    // Images
    'image/png', 'image/jpeg', 'image/jpg', 'image/tiff', 'image/tif',
    'image/gif', 'image/webp', 'image/bmp', 'image/svg+xml', 'image/heic',
    // Videos
    'video/mp4', 'video/mpeg', 'video/mpg', 'video/x-ms-wmv',
    'video/quicktime', 'video/x-msvideo', 'video/webm', 'video/x-matroska',
    // Audio
    'audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/aac', 'audio/ogg',
    'audio/m4a', 'audio/flac', 'audio/x-m4a',
    // Documents
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain', 'text/csv',
    'application/zip', 'application/x-zip-compressed', 'application/x-rar-compressed'
  ];
  
  // Check file extension as fallback
  const ext = path.extname(file.originalname).toLowerCase();
  const allowedExtensions = [
    '.png', '.jpeg', '.jpg', '.tiff', '.tif', '.gif', '.webp', '.bmp', '.svg', '.heic',
    '.mp4', '.mpeg', '.mpg', '.wmv', '.mov', '.avi', '.webm', '.mkv',
    '.mp3', '.wav', '.aac', '.ogg', '.m4a', '.flac',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.txt', '.csv', '.zip', '.rar'
  ];
  
  if (allowed.includes(file.mimetype) || allowedExtensions.includes(ext)) {
    cb(null, true);
  } else {
    console.log('❌ Unsupported file type:', file.mimetype, ext);
    cb(new Error(`Unsupported file type: ${file.mimetype}`), false);
  }
};

// Multer instance for general file uploads
export const upload = multer({
  storage,
  fileFilter,
  limits: { 
    fileSize: config.maxFileSize,
    files: 1 // Single file upload
  }
});

// Multer instance specifically for voice messages
export const voiceUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      cb(null, voicesDir);
    },
    filename: (req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase();
      const uniqueName = `voice_${Date.now()}_${Math.round(Math.random() * 1E9)}${ext}`;
      cb(null, uniqueName);
    },
  }),
  fileFilter: (req, file, cb) => {
    const audioMimes = ['audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/aac', 'audio/ogg', 'audio/m4a', 'audio/x-m4a'];
    const ext = path.extname(file.originalname).toLowerCase();
    const audioExts = ['.mp3', '.wav', '.aac', '.ogg', '.m4a'];
    
    if (audioMimes.includes(file.mimetype) || audioExts.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Only audio files are allowed for voice messages'), false);
    }
  },
  limits: { 
    fileSize: 10 * 1024 * 1024, // 10MB for voice
    files: 1
  }
});

