// dotenv is loaded in config/index.js
import express from 'express';
import mongoose from 'mongoose';
import cors from 'cors';
import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import path from 'path';
import { fileURLToPath } from 'url';
import config from './config/index.js';

// Import routes
import authRoutes from './routes/authRoutes.js';
import messageRoutes from './routes/messageRoutes.js';
import conversationRoutes from './routes/conversationRoutes.js';
import userRoutes from './routes/userRoutes.js';
import groupRoutes from './routes/groupRoutes.js';
import notificationRoutes from './routes/notificationRoutes.js';

// Import services
import PresenceService from './services/presenceService.js';
import MessageService from './services/messageService.js';
import CallService from './services/callService.js';
import NotificationService from './services/notificationService.js';

// Import socket handler
import initializeSockets from './sockets/socketHandler.js';

// Import controllers
import { setGroupService } from './controllers/groupController.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize Express app
const app = express();
const server = http.createServer(app);

// Initialize Socket.IO
const io = new SocketIOServer(server, {
  cors: {
    origin: config.allowedOrigins.length > 0 ? config.allowedOrigins : '*',
    credentials: true
  }
});

// Attach io to app for access in controllers
app.set('io', io);

// ============ MIDDLEWARES ============

// CORS
app.use(cors({
  origin: config.allowedOrigins.length > 0 ? config.allowedOrigins : '*',
  credentials: true
}));

// Body parsing
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Static files
const uploadsPath = path.join(__dirname, '../', config.uploadDir);
app.use('/uploads', express.static(uploadsPath));

// Health check
app.get('/health', async (req, res) => {
  const dbStatus = mongoose.connection.readyState;
  const dbStates = {
    0: 'disconnected',
    1: 'connected',
    2: 'connecting',
    3: 'disconnecting'
  };
  
  const isHealthy = dbStatus === 1; // 1 = connected
  
  res.status(isHealthy ? 200 : 503).json({
    success: isHealthy,
    status: isHealthy ? 'ok' : 'unhealthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    database: {
      status: dbStates[dbStatus] || 'unknown',
      connected: dbStatus === 1,
      host: mongoose.connection.host || 'unknown',
      name: mongoose.connection.name || 'unknown'
    }
  });
});

// Database connection check endpoint
app.get('/health/db', async (req, res) => {
  try {
    // Try a simple database operation
    await mongoose.connection.db.admin().ping();
    
    res.json({
      success: true,
      status: 'connected',
      timestamp: new Date().toISOString(),
      database: {
        host: mongoose.connection.host,
        name: mongoose.connection.name,
        readyState: mongoose.connection.readyState
      }
    });
  } catch (error) {
    res.status(503).json({
      success: false,
      status: 'disconnected',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// ============ DATABASE CONNECTION ============

// MongoDB connection options with proper timeout settings
const mongooseOptions = {
  serverSelectionTimeoutMS: 10000, // 10 seconds - how long to wait for server selection
  socketTimeoutMS: 45000, // 45 seconds - how long to wait for socket operations
  connectTimeoutMS: 10000, // 10 seconds - how long to wait for initial connection
  maxPoolSize: 10, // Maximum number of connections in the pool
  minPoolSize: 2, // Minimum number of connections in the pool
  retryWrites: true, // Retry write operations on network errors
  retryReads: true, // Retry read operations on network errors
};

// Set up connection event handlers before connecting
mongoose.connection.on('connected', () => {
  console.log('✅ MongoDB Connected to:', config.mongodbUri.replace(/\/\/.*@/, '//***@'));
});

mongoose.connection.on('error', (err) => {
  console.error('❌ MongoDB Connection Error:', err.message);
});

mongoose.connection.on('disconnected', () => {
  console.warn('⚠️  MongoDB Disconnected');
});

mongoose.connection.on('reconnected', () => {
  console.log('🔄 MongoDB Reconnected');
});

// Handle process termination
process.on('SIGINT', async () => {
  await mongoose.connection.close();
  process.exit(0);
});

// Connect to MongoDB with retry logic
const connectWithRetry = async (retries = 5, delay = 5000) => {
  for (let i = 0; i < retries; i++) {
    try {
      await mongoose.connect(config.mongodbUri, mongooseOptions);
      console.log('✅ MongoDB connection established');
      return;
    } catch (err) {
      console.error(`❌ MongoDB connection attempt ${i + 1}/${retries} failed:`, err.message);
      if (i < retries - 1) {
        console.log(`⏳ Retrying in ${delay / 1000} seconds...`);
        await new Promise(resolve => setTimeout(resolve, delay));
      } else {
        console.error('❌ Failed to connect to MongoDB after', retries, 'attempts');
        console.log('Please check:');
        console.log('  1. MongoDB is running');
        console.log('  2. MONGODB_URI is correct in your .env file');
        console.log('  3. Network connectivity');
        process.exit(1);
      }
    }
  }
};

connectWithRetry();

// ============ INITIALIZE SERVICES ============

const presenceService = new PresenceService(io);
const callService = new CallService(io);
const notificationService = new NotificationService(io, presenceService);
const messageService = new MessageService(io, presenceService, notificationService);

// Initialize Group Service (requires io)
setGroupService(io);

// Store services on app for access in controllers
app.set('presenceService', presenceService);
app.set('callService', callService);
app.set('messageService', messageService);
app.set('notificationService', notificationService);

// Initialize Socket.IO with services
const services = {
  messageService,
  presenceService,
  callService,
  notificationService
};
initializeSockets(io, services);

// ============ ROUTES ============

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/conversations', conversationRoutes);
app.use('/api/users', userRoutes);
app.use('/api/groups', groupRoutes);
app.use('/api/notifications', notificationRoutes);

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Backend2 API Server',
    version: '1.0.0',
    endpoints: {
      auth: '/api/auth',
      messages: '/api/messages',
      conversations: '/api/conversations',
      users: '/api/users',
      groups: '/api/groups',
      notifications: '/api/notifications'
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'not_found',
    message: `Route ${req.method} ${req.path} not found`
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('❌ Error:', err);
  
  // Multer errors
  if (err.name === 'MulterError') {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({
        success: false,
        error: 'file_too_large',
        message: `File size exceeds maximum allowed size of ${config.maxFileSize / 1024 / 1024}MB`
      });
    }
  }

  // Validation errors
  if (err.name === 'ValidationError') {
    return res.status(400).json({
      success: false,
      error: 'validation_error',
      message: Object.values(err.errors).map(e => e.message).join(', ')
    });
  }

  // Default error
  res.status(err.status || 500).json({
    success: false,
    error: err.name || 'server_error',
    message: err.message || 'Internal server error'
  });
});

// ============ START SERVER ============

const PORT = config.port;

server.listen(PORT, () => {
  console.log('═══════════════════════════════════════════════════');
  console.log('🚀 Backend2 Server Started Successfully!');
  console.log('═══════════════════════════════════════════════════');
  console.log(`📡 Server running on: http://localhost:${PORT}`);
  console.log(`🌍 Environment: ${config.nodeEnv}`);
  console.log(`📊 MongoDB: ${config.mongodbUri.replace(/\/\/.*@/, '//***@')}`);
  console.log(`🔐 CORS Origins: ${config.allowedOrigins.join(', ')}`);
  console.log('═══════════════════════════════════════════════════');
});

// Handle server errors
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.log(`❌ Port ${PORT} is already in use.`);
    console.log('💡 Please kill the process using this port or use a different port.');
    process.exit(1);
  } else {
    console.error('❌ Server error:', err);
    process.exit(1);
  }
});

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  console.log(`🛑 ${signal} received, shutting down gracefully...`);
  
  // Close HTTP server
  server.close(() => {
    console.log('✅ HTTP server closed');
  });
  
  // Close MongoDB connection (Mongoose 8+ uses Promise, not callback)
  try {
    await mongoose.connection.close();
    console.log('✅ MongoDB connection closed');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error closing MongoDB connection:', error);
    process.exit(1);
  }
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

export default app;

