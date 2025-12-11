# Backend2 Integration Status

## Overview
This document tracks what services, controllers, and features are integrated and what's still needed for full compatibility with both Backend (Electron) and Backend1 (Flutter).

---

## ✅ Completed

### Core Infrastructure
- [x] Project structure (modular architecture)
- [x] Configuration system with environment validation
- [x] Models (User, Message, Conversation, Group, Otp, Session)
- [x] Authentication middleware (supports both JWT formats)
- [x] Rate limiting middleware
- [x] Upload middleware (files + voice)
- [x] Utilities (phone normalizer, constants)
- [x] Group model, service, controller, routes

---

## 🚧 Still Need Integration

### 1. Authentication System (CRITICAL)
**Status**: ❌ Not Started  
**Priority**: 🔴 HIGH

**From Backend:**
- Session-based authentication
- Session model integration

**From Backend1:**
- OTP generation (database-backed)
- OTP verification for registration
- OTP verification for login
- Password login (optional)

**Files Needed:**
- `src/controllers/authController.js`
- `src/routes/authRoutes.js`

**Features:**
- [ ] `POST /auth/send-otp` - Send OTP (database-backed, not in-memory)
- [ ] `POST /auth/verify-otp-register` - Register with OTP
- [ ] `POST /auth/send-otp-login` - Request login OTP
- [ ] `POST /auth/verify-otp-login` - Login with OTP
- [ ] `POST /auth/login` - Password login
- [ ] `GET /auth/me` - Get current user

---

### 2. Message Service (CRITICAL)
**Status**: ❌ Not Started  
**Priority**: 🔴 HIGH

**From Backend:**
- MessageService class with broadcast methods
- Notification creation

**From Backend1:**
- Cursor-based delivered receipts
- Message editing support
- Reply/quote functionality
- Call activity messages

**Files Needed:**
- `src/services/messageService.js`

**Features:**
- [ ] Send message (supports both `from/to` and `sender`)
- [ ] Broadcast to conversation members
- [ ] Cursor-based delivered receipts (`deliveredUpTo`)
- [ ] Cursor-based read receipts (`readUpTo`)
- [ ] Message editing
- [ ] Message reactions
- [ ] Reply functionality
- [ ] Delete message (soft delete, support both styles)
- [ ] Search messages

---

### 3. Presence Service (CRITICAL)
**Status**: ❌ Not Started  
**Priority**: 🔴 HIGH

**From Backend:**
- PresenceService class
- Multi-device support
- Typing indicators

**From Backend1:**
- Cursor-based receipt catchup
- Session counting
- Presence timestamps

**Files Needed:**
- `src/services/presenceService.js`

**Features:**
- [ ] User connection tracking (multi-device)
- [ ] Online/offline status (with session counting)
- [ ] Presence broadcasting
- [ ] Typing indicators
- [ ] Delivered receipt catchup on connect
- [ ] User status queries

---

### 4. Call Service (HIGH)
**Status**: ❌ Not Started  
**Priority**: 🟡 MEDIUM-HIGH

**From Backend1:**
- WebRTC call signaling
- Call state management
- Call timeout handling
- Audio/video call support

**Files Needed:**
- `src/services/callService.js`

**Features:**
- [ ] Call invitation (`call:invite`)
- [ ] Call answer/reject (`call:answer`)
- [ ] ICE candidate relay (`call:candidate`)
- [ ] Call hangup (`call:hangup`)
- [ ] Call timeout (40 seconds)
- [ ] Busy user detection
- [ ] Call state persistence (database or Redis)
- [ ] Support both audio and video calls

---

### 5. Notification Service (MEDIUM)
**Status**: ❌ Not Started  
**Priority**: 🟡 MEDIUM

**From Backend:**
- Notification model exists
- Notification creation for messages

**Files Needed:**
- `src/models/Notification.js` (update/create if needed)
- `src/services/notificationService.js`

**Features:**
- [ ] Create message notifications
- [ ] Mark as read
- [ ] Get user notifications
- [ ] Get unread count
- [ ] Notification cleanup

---

### 6. Message Controller & Routes (CRITICAL)
**Status**: ❌ Not Started  
**Priority**: 🔴 HIGH

**From Backend:**
- RESTful message endpoints
- Pagination support

**From Backend1:**
- Message editing endpoint
- Call activity support
- Reply functionality

**Files Needed:**
- `src/controllers/messageController.js`
- `src/routes/messageRoutes.js`

**Endpoints:**
- [ ] `POST /messages` - Send message (supports both formats)
- [ ] `GET /messages` - Get messages (with pagination, supports both query styles)
- [ ] `PATCH /messages/:id` - Edit message
- [ ] `DELETE /messages/:id` - Delete message
- [ ] `POST /messages/voice` - Upload voice message
- [ ] `POST /messages/upload` - Upload file
- [ ] `GET /messages/search` - Search messages

---

### 7. Conversation Controller & Routes (HIGH)
**Status**: ❌ Not Started  
**Priority**: 🟡 HIGH

**From Backend:**
- Conversation CRUD
- Participant management

**From Backend1:**
- Chat request workflow
- Contact sync
- Direct chat creation

**Files Needed:**
- `src/controllers/conversationController.js`
- `src/routes/conversationRoutes.js`

**Endpoints:**
- [ ] `GET /conversations` - Get user's conversations (with cursor receipts)
- [ ] `POST /conversations` - Create conversation
- [ ] `GET /conversations/:id` - Get conversation details
- [ ] `DELETE /conversations/:id` - Delete/hide conversation
- [ ] `POST /chat-requests` - Send chat request (Backend1)
- [ ] `POST /chat-requests/:id/accept` - Accept request
- [ ] `POST /chat-requests/:id/decline` - Decline request
- [ ] `GET /chat-requests` - Get chat requests
- [ ] `POST /contacts/start-chat` - Start chat directly (Backend1)
- [ ] `POST /contacts/sync` - Sync contacts (Backend1)

---

### 8. User Controller & Routes (MEDIUM)
**Status**: ❌ Not Started  
**Priority**: 🟡 MEDIUM

**From Backend:**
- User profile management
- User search
- Status management

**Files Needed:**
- `src/controllers/userController.js`
- `src/routes/userRoutes.js`

**Endpoints:**
- [ ] `GET /users` - Get users (with search, pagination)
- [ ] `GET /users/search` - Search users
- [ ] `GET /users/profile` - Get current user
- [ ] `GET /users/profile/:userId` - Get user profile
- [ ] `PATCH /users/me` - Update profile (supports both `avatar` and `avatarUrl`)
- [ ] `GET /users/by-ids` - Get users by IDs (Backend1)
- [ ] `GET /presence` - Get presence status (Backend1 style)
- [ ] `GET /users/online/count` - Get online count

---

### 9. Socket.IO Handlers (CRITICAL)
**Status**: ❌ Not Started  
**Priority**: 🔴 HIGH

**From Backend:**
- Message broadcasting
- Typing indicators
- Presence tracking
- Message reactions

**From Backend1:**
- Cursor-based receipts
- Call signaling
- Chat request notifications
- Delivered catchup on connect

**Files Needed:**
- `src/sockets/socketHandler.js`

**Socket Events:**
- [ ] Connection/auth handling
- [ ] `send-message` / `message` - Send message
- [ ] `receive-message` - Receive message broadcast
- [ ] `message_edited` - Message edited
- [ ] `message_deleted` - Message deleted
- [ ] `delivered` - Delivery confirmation (cursor-based)
- [ ] `read_up_to` - Read receipts (cursor-based)
- [ ] `catchupDelivered` - Catchup on connect
- [ ] `typing` / `typing-stopped` - Typing indicators
- [ ] `call:invite` - Call invitation
- [ ] `call:answer` - Call answer
- [ ] `call:candidate` - ICE candidate
- [ ] `call:hangup` - Call hangup
- [ ] `presence` - Presence updates
- [ ] `chat_request` - Chat request notification
- [ ] `user_profile_updated` - Profile update broadcast
- [ ] Disconnect handling with cleanup

---

### 10. Main Server File (CRITICAL)
**Status**: ❌ Not Started  
**Priority**: 🔴 HIGH

**Files Needed:**
- `src/index.js`

**Features:**
- [ ] Express app setup
- [ ] MongoDB connection with error handling
- [ ] Socket.IO server setup with CORS
- [ ] Route registration (auth, users, messages, conversations, groups)
- [ ] Static file serving (uploads)
- [ ] Global error handling
- [ ] Server startup with health check

---

## 📊 Compatibility Matrix

### API Endpoints Compatibility

| Endpoint | Backend (Electron) | Backend1 (Flutter) | Backend2 Status |
|----------|-------------------|-------------------|-----------------|
| Auth | ✅ | ✅ | ❌ Not Started |
| Users | ✅ | ✅ | ❌ Not Started |
| Messages | ✅ | ✅ | ❌ Not Started |
| Conversations | ✅ | ✅ | ❌ Not Started |
| Groups | ✅ | ❌ | ✅ Completed |
| Presence | ✅ | ✅ | ❌ Not Started |
| Calls | ⚠️ Basic | ✅ Advanced | ❌ Not Started |
| Contacts | ❌ | ✅ | ❌ Not Started |
| Chat Requests | ❌ | ✅ | ❌ Not Started |

### Socket Events Compatibility

| Event | Backend | Backend1 | Backend2 Status |
|-------|---------|----------|-----------------|
| `send-message` | ✅ | ❌ | Need unified |
| `message` | ❌ | ✅ | Need unified |
| `receive-message` | ✅ | ❌ | Need unified |
| `delivered` | ⚠️ Per-msg | ✅ Cursor | Need cursor |
| `read_up_to` | ❌ | ✅ Cursor | Need cursor |
| `typing` | ✅ | ✅ | Need unified |
| `call:*` | ⚠️ Basic | ✅ Advanced | Need advanced |
| `presence` | ✅ | ✅ | Need unified |
| `chat_request` | ❌ | ✅ | Need to add |

---

## 🎯 Implementation Priority

### Phase 1: Critical Path (Week 1)
1. ✅ Group Service (Done)
2. **Auth Controller & Routes** - Required for all endpoints
3. **Main Server File** - Get server running
4. **Socket Handlers (Basic)** - Real-time communication

### Phase 2: Core Features (Week 2)
5. **Message Service** - Core messaging
6. **Message Controller & Routes** - REST API
7. **Presence Service** - Online/offline tracking
8. **Socket Handlers (Complete)** - All events

### Phase 3: Enhanced Features (Week 3)
9. **Conversation Controller & Routes** - Chat management
10. **Call Service** - WebRTC signaling
11. **User Controller & Routes** - Profile management
12. **Notification Service** - Notifications

### Phase 4: Polish (Week 4)
13. Testing
14. Documentation
15. Performance optimization
16. Security audit

---

## 📝 Field Mapping Reminders

### Messages
- Support both `from/to` (Backend1) and `sender` (Backend)
- Support both `text` (Backend1) and `content` (Backend)
- Support both `conversation` (Backend1) and `conversationId` (Backend)
- Auto-sync in model pre-save hooks

### Conversations
- Support both `participants` (Backend1) and `members` (Backend)
- Support `status` from Backend1
- Support `participantKey` from Backend

### Users
- Support both `avatar` (Backend) and `avatarUrl` (Backend1)
- Support both `id`, `uid`, `userId` in responses

### Responses
- Use unified format: `{ success: true/false, data, error, message }`
- Support both field naming conventions in responses

---

## 🚀 Next Steps

1. **Start with Auth** - Everything depends on authentication
2. **Create Main Server** - Get basic server running
3. **Implement Socket Handlers** - Real-time is core feature
4. **Add Message Service** - Core functionality
5. **Build Controllers** - REST API layer
6. **Add Services** - Business logic abstraction

---

## 📚 Reference Files

### Backend (Electron)
- `backend/services/messageService.js`
- `backend/services/presenceService.js`
- `backend/controllers/*.js`
- `backend/routes/*.js`
- `backend/sockets/socketHandler.js`

### Backend1 (Flutter)
- `backend1/src/index.js` - All handlers inline
- `backend1/src/auth.js` - Auth routes
- Models in `backend1/src/models/`

---

**Last Updated**: Now  
**Status**: 1/10 critical components complete (10%)
