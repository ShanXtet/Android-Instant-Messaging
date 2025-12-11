import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from confi.env (or .env if it exists)
dotenv.config({ path: path.join(__dirname, '../../confi.env') });
// Also try loading .env as fallback
dotenv.config({ path: path.join(__dirname, '../../.env') });

// Validate required environment variables
const requiredEnvVars = ['JWT_SECRET'];
const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);

if (missingVars.length > 0) {
  console.error('❌ Missing required environment variables:', missingVars.join(', '));
  console.error('Please check your .env file');
  process.exit(1);
}

// MongoDB URI with default for local development
const defaultMongoUri = 'mongodb://localhost:27017/messenger';
const mongodbUri = process.env.MONGODB_URI || defaultMongoUri;

if (!process.env.MONGODB_URI) {
  console.warn('⚠️  MONGODB_URI not set, using default:', defaultMongoUri);
  console.warn('   To use a different database, set MONGODB_URI in your .env file');
}

// Validate JWT_SECRET is not default
if (process.env.JWT_SECRET === 'your-super-secret-jwt-key-change-in-production' || 
    process.env.JWT_SECRET === 'devsecret') {
  if (process.env.NODE_ENV === 'production') {
    console.error('❌ JWT_SECRET must be changed from default value in production!');
    process.exit(1);
  } else {
    console.warn('⚠️  Using default JWT_SECRET. Change this in production!');
  }
}

export default {
  // Server
  port: parseInt(process.env.PORT || '5000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  
  // MongoDB
  mongodbUri: mongodbUri,
  
  // JWT
  jwtSecret: process.env.JWT_SECRET,
  jwtExpiry: process.env.JWT_EXPIRY || '7d',
  
  // CORS
  allowedOrigins: process.env.ALLOWED_ORIGINS?.split(',') || [
    'http://localhost:3000',
    'http://localhost:8080'
  ],
  
  // File Upload
  maxFileSize: parseInt(process.env.MAX_FILE_SIZE || '52428800', 10), // 50MB
  uploadDir: process.env.UPLOAD_DIR || './uploads',
  
  // Rate Limiting
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10), // 15 minutes
    max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '200', 10) // Increased from 100 to 200 for development
  },
  
  // OTP
  otpExpiryMinutes: parseInt(process.env.OTP_EXPIRY_MINUTES || '5', 10),
  
  // Redis (optional)
  redisUrl: process.env.REDIS_URL,
  
  // Call Configuration
  callTimeoutMs: 40000, // 40 seconds
  
  // Message Limits
  maxMessageLength: 4000,
  messagesPerPage: 50,
};

