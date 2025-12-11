# Backend2 - Unified Messaging Backend

## Overview

Backend2 is a unified messaging backend that combines the best features from:
- **Backend** (Desktop/Electron app support)
- **Backend1** (Mobile/Flutter app support)

It supports both Electron desktop and Flutter mobile clients with a consistent API.

## Architecture

### Key Features Combined

✅ **From Backend (Desktop):**
- Structured MVC architecture
- Database-backed sessions
- Service layer abstraction
- Pagination support
- Session management

✅ **From Backend1 (Mobile):**
- Cursor-based read/delivered receipts (more efficient)
- Advanced WebRTC call signaling
- Chat request workflow
- Contact sync functionality

✅ **New Improvements:**
- Security fixes (CORS, rate limiting, input validation)
- Unified data models (supports both field naming conventions)
- Better error handling
- Production-ready configuration

## Structure

```
backend2/
├── src/
│   ├── config/          # Configuration
│   ├── controllers/     # Route handlers
│   ├── middlewares/     # Auth, validation, rate limiting
│   ├── models/          # Mongoose models (unified)
│   ├── routes/          # API routes
│   ├── services/        # Business logic layer
│   ├── sockets/         # Socket.IO handlers
│   ├── utils/           # Helper functions
│   └── index.js         # Main server file
├── uploads/             # File uploads
└── package.json
```

## Setup

1. **Install Dependencies**
```bash
cd backend2
npm install
```

2. **Configure Environment**
```bash
cp .env.example .env
# Edit .env with your settings
```

3. **Start Server**
```bash
npm start
# or for development
npm run dev
```

## API Compatibility

### Supporting Both Clients

The API is designed to support both Electron and Flutter clients:

#### Field Name Mapping

**Messages:**
- Supports both `from/to` (Backend1) and `sender` (Backend)
- Supports both `conversation` and `conversationId`
- Supports both `text` and `content`

**Conversations:**
- Supports both `participants` (Backend1) and `members` (Backend)
- Auto-generates `participantKey` for direct conversations

**Users:**
- Supports both `avatar` and `avatarUrl`

#### Authentication

Supports both authentication styles:
- Simple JWT (Backend1): `{ uid: userId }`
- Session-based JWT (Backend): `{ id: userId, sessionId: ... }`

## API Endpoints

### Authentication
- `POST /auth/send-otp` - Send OTP
- `POST /auth/verify-otp-register` - Register with OTP
- `POST /auth/send-otp-login` - Request login OTP
- `POST /auth/verify-otp-login` - Login with OTP
- `POST /auth/login` - Password login

### Messages
- `GET /messages` - Get messages (with pagination)
- `POST /messages` - Send message
- `PATCH /messages/:id` - Edit message
- `DELETE /messages/:id` - Delete message

### Conversations
- `GET /conversations` - Get conversations
- `POST /conversations` - Create conversation
- `POST /chat-requests` - Send chat request
- `POST /chat-requests/:id/accept` - Accept request
- `POST /contacts/start-chat` - Start chat directly

### Users
- `GET /users` - Get users
- `GET /users/profile` - Get current user
- `PATCH /users/me` - Update profile
- `POST /contacts/sync` - Sync contacts

## Socket.IO Events

### Connection
- `connection` - Client connects (requires auth token)
- `disconnect` - Client disconnects

### Messages
- `message` - New message received
- `message_edited` - Message edited
- `message_deleted` - Message deleted

### Receipts
- `delivered` - Message delivered
- `read_up_to` - Messages read up to timestamp

### Typing
- `typing` - User typing
- `typing-stopped` - User stopped typing

### Calls
- `call:invite` - Call invitation
- `call:answer` - Call answered
- `call:candidate` - ICE candidate
- `call:hangup` - Call ended

### Presence
- `presence` - User online/offline status
- `user-status-changed` - Status change notification

## Features

### Cursor-Based Receipts

More efficient than per-message receipts:
- `deliveredUpTo: Map<userId, Date>` - Last delivered timestamp per user
- `readUpTo: Map<userId, Date>` - Last read timestamp per user

### Multi-Device Support

Users can connect from multiple devices:
- Each device maintains separate socket connection
- Presence tracking counts active sessions
- Messages broadcast to all user's devices

### Call Signaling

Advanced WebRTC call handling:
- Audio and video calls
- ICE candidate relay
- Call timeout (40 seconds)
- Busy user detection
- Automatic cleanup on disconnect

## Migration Guide

### From Backend (Desktop)

1. Field names are backward compatible
2. Session management is enhanced
3. Receipt system upgraded to cursors

### From Backend1 (Mobile)

1. OTP storage moved to database
2. In-memory state moved to database/Redis
3. Better error handling and validation

## Environment Variables

See `.env.example` for all required variables.

**Required:**
- `MONGODB_URI` - MongoDB connection string
- `JWT_SECRET` - JWT signing secret

**Optional:**
- `PORT` - Server port (default: 5000)
- `ALLOWED_ORIGINS` - CORS allowed origins
- `REDIS_URL` - Redis for scaling (optional)

## Security

- ✅ CORS configuration (not wildcard)
- ✅ Rate limiting on all endpoints
- ✅ Input validation
- ✅ JWT secret validation
- ✅ Secure file uploads
- ✅ Password hashing

## Performance

- ✅ Database indexes on all queries
- ✅ Pagination support
- ✅ Efficient cursor-based receipts
- ✅ Socket.IO rooms for broadcasting
- ✅ Lean queries for read operations

## Development

```bash
# Development mode with auto-reload
npm run dev

# Production mode
npm start
```

## Testing

Test endpoints (development only):
- `GET /ping` - Health check
- `GET /health` - Detailed health status

## License

MIT

