# Backend2 Integration Plan

## Overview

This document outlines the integration strategy for combining Backend (Electron) and Backend1 (Flutter) into Backend2.

## Integration Strategy

### Phase 1: Core Structure ✅ (Completed)
- [x] Create directory structure
- [x] Unified models (User, Message, Conversation)
- [x] Configuration system
- [x] Authentication middleware

### Phase 2: Authentication & Routes (In Progress)
- [ ] Auth controller (OTP + password)
- [ ] Auth routes
- [ ] User controller
- [ ] User routes
- [ ] Message controller
- [ ] Message routes
- [ ] Conversation controller
- [ ] Conversation routes

### Phase 3: Services Layer
- [ ] Message service
- [ ] Presence service
- [ ] Call service
- [ ] Notification service

### Phase 4: Socket.IO Handlers
- [ ] Connection/auth handler
- [ ] Message handlers
- [ ] Receipt handlers (cursor-based)
- [ ] Typing indicators
- [ ] Call signaling
- [ ] Presence tracking

### Phase 5: Utilities & Helpers
- [ ] Phone normalizer
- [ ] Constants
- [ ] Error handlers
- [ ] Validators

### Phase 6: Testing & Documentation
- [ ] API documentation
- [ ] Client migration guides
- [ ] Testing

## Field Mapping Strategy

### Messages
```javascript
// Backend1 uses: from, to, text, conversation
// Backend uses: sender, content, conversationId

// Solution: Support both, auto-sync in pre-save hook
{
  from: ObjectId,      // Backend1
  sender: ObjectId,    // Backend (synced)
  to: ObjectId,        // Backend1
  text: String,        // Backend1
  content: String,     // Backend (synced)
  conversation: ObjectId,    // Backend1
  conversationId: ObjectId   // Backend (synced)
}
```

### Conversations
```javascript
// Backend1 uses: participants, status
// Backend uses: members, isGroup

// Solution: Support both, auto-sync
{
  participants: [ObjectId],  // Backend1
  members: [ObjectId],       // Backend (synced)
  status: String,            // Backend1
  isGroup: Boolean,          // Backend
  participantKey: String     // Backend (unique key)
}
```

### Users
```javascript
// Backend1 uses: avatarUrl
// Backend uses: avatar

// Solution: Support both
{
  avatar: String,      // Backend
  avatarUrl: String    // Backend1 (synced)
}
```

## API Endpoint Strategy

### Unified Endpoints
Both clients can use the same endpoints. Response format adapts based on:
1. Request headers (`Client-Type: electron` or `Client-Type: flutter`)
2. Query parameters
3. Auto-detection based on field names used

### Backward Compatibility
- All Backend endpoints: `/api/*`
- All Backend1 endpoints: Direct paths
- Support both naming conventions in responses

## Socket.IO Strategy

### Event Names
- Use new unified event names
- Support legacy events for backward compatibility
- Document migration path

### Authentication
- Support both JWT formats
- Socket auth via `socket.handshake.auth.token`

## Database Strategy

### Migration
1. Support both field naming conventions
2. Pre-save hooks sync fields
3. Eventually migrate to single convention

### Indexes
- Index all query patterns
- Support both field name variations

## Security Improvements

1. **CORS**: Configurable origins (not wildcard)
2. **Rate Limiting**: All endpoints protected
3. **Input Validation**: express-validator
4. **JWT Secret**: No default fallback
5. **File Uploads**: Size limits, type validation

## Performance Improvements

1. **Cursor Receipts**: More efficient than per-message
2. **Pagination**: All list endpoints
3. **Indexes**: Comprehensive coverage
4. **Lean Queries**: Read-only operations
5. **Socket.IO Rooms**: Efficient broadcasting

## Client Migration Path

### Electron (Backend → Backend2)
- Minimal changes needed
- Field names backward compatible
- Session management enhanced

### Flutter (Backend1 → Backend2)
- OTP storage now database-backed
- Cursor receipts work the same way
- API endpoints largely compatible

## Next Steps

1. Complete authentication system
2. Create all controllers
3. Implement services layer
4. Add Socket.IO handlers
5. Test with both clients
6. Deploy and monitor

