# Group Features Documentation

## Overview

Backend2 includes comprehensive group chat functionality with a dedicated Group model, service layer, and full CRUD operations.

## Group Model

The Group model (`src/models/Group.js`) includes:

### Core Fields
- `name` - Group name (required, max 100 chars)
- `description` - Group description (optional, max 500 chars)
- `admin` - Main admin (required)
- `admins` - Array of admin user IDs
- `participants` / `members` - Array of member user IDs (synced)
- `avatar` / `avatarUrl` - Group avatar image (synced)
- `conversation` / `conversationId` - Linked conversation (1:1 relationship)

### Settings
- `settings.onlyAdminsCanSendMessages` - Restrict messaging
- `settings.onlyAdminsCanAddMembers` - Restrict member addition
- `settings.isPublic` - Public/private group
- `settings.inviteLink` - Unique invite link

### Metadata
- `memberCount` - Auto-calculated member count
- `lastActivity` - Last activity timestamp

## Group Service

The GroupService (`src/services/groupService.js`) provides:

### Core Operations
- `createGroup()` - Create group with linked conversation
- `getGroupDetails()` - Get group with member check
- `getUserGroups()` - Get user's groups with pagination
- `updateGroup()` - Update group details (admin only)

### Member Management
- `addParticipant()` - Add member to group
- `removeParticipant()` - Remove member from group
- `leaveGroup()` - User leaves group
- `promoteToAdmin()` - Promote member to admin
- `demoteAdmin()` - Demote admin to member

### Invite System
- `generateInviteLink()` - Generate unique invite link
- `joinViaInviteLink()` - Join group via link

### Search
- `searchGroups()` - Search user's groups by name

## API Endpoints

### Create Group
```
POST /api/groups
POST /api/groups/create

Body:
{
  "name": "My Group",
  "description": "Group description",
  "participants": ["userId1", "userId2"],
  "avatar": "url/to/avatar.jpg"
}
```

### Get User's Groups
```
GET /api/groups?page=1&limit=20&search=query
```

### Get Group Details
```
GET /api/groups/:groupId
```

### Add Participant
```
POST /api/groups/add-participant

Body:
{
  "groupId": "group123",
  "userId": "user456"
}
```

### Remove Participant
```
POST /api/groups/remove-participant

Body:
{
  "groupId": "group123",
  "userId": "user456"
}
```

### Update Group
```
PUT /api/groups/:groupId
PATCH /api/groups/:groupId

Body:
{
  "name": "New Name",
  "description": "New description",
  "avatar": "new-avatar-url",
  "settings": {
    "onlyAdminsCanSendMessages": true
  }
}
```

### Leave Group
```
DELETE /api/groups/:groupId/leave
```

### Promote to Admin
```
POST /api/groups/promote-admin

Body:
{
  "groupId": "group123",
  "userId": "user456"
}
```

### Generate Invite Link
```
GET /api/groups/:groupId/invite-link
```

### Join via Invite Link
```
POST /api/groups/join

Body:
{
  "inviteLink": "generated-link-here"
}
```

### Search Groups
```
GET /api/groups/search?query=groupname&limit=20
```

## Integration with Conversations

### Automatic Conversation Creation

When a group is created:
1. Group is created with participants
2. Associated conversation is automatically created
3. Conversation is linked to group (1:1 relationship)
4. Conversation has `isGroup: true`

### Member Synchronization

When members are added/removed from group:
- Conversation participants/members are automatically updated
- Both Group and Conversation stay in sync

## Usage Examples

### Creating a Group
```javascript
// Frontend code
const response = await fetch('/api/groups', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    name: 'Development Team',
    description: 'Team chat for developers',
    participants: ['user1', 'user2', 'user3']
  })
});

const { group, conversation } = await response.json();
// Use conversation._id for sending messages
```

### Adding Members
```javascript
await fetch('/api/groups/add-participant', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    groupId: 'group123',
    userId: 'newUser456'
  })
});
```

### Getting User's Groups
```javascript
const response = await fetch('/api/groups?page=1&limit=20', {
  headers: {
    'Authorization': `Bearer ${token}`
  }
});

const { groups, pagination } = await response.json();
```

## Permissions

### Admin Permissions
- Update group details
- Add/remove members
- Promote/demote admins
- Generate invite links

### Member Permissions
- View group details
- Leave group
- Send messages (unless restricted by settings)

### Group Settings
- `onlyAdminsCanSendMessages`: If true, only admins can send messages
- `onlyAdminsCanAddMembers`: If true, only admins can add new members

## Best Practices

1. **Always check permissions** before operations
2. **Sync group and conversation** when updating members
3. **Use pagination** when fetching user's groups
4. **Handle invite links securely** - they provide direct access
5. **Update lastActivity** when group is active

## Socket.IO Events

Groups work with existing message/conversation socket events:
- `message` - New message in group conversation
- `message_edited` - Message edited
- `message_deleted` - Message deleted
- Group-specific events can be added as needed

## Database Indexes

Optimized indexes for:
- `admin` - Quick admin lookup
- `participants` - Member queries
- `conversation` - Group-conversation link
- `settings.inviteLink` - Invite link lookups
- `lastActivity` - Activity-based sorting

## Error Handling

All endpoints return consistent error format:
```javascript
{
  "success": false,
  "error": "error_code",
  "message": "Human readable message"
}
```

Common error codes:
- `validation_error` - Invalid input
- `not_found` - Group not found
- `forbidden` - Permission denied
- `server_error` - Internal error

