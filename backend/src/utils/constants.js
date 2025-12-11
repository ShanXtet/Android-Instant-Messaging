/**
 * Application constants
 */

export const MESSAGE_STATUS = {
  SENT: 'sent',
  DELIVERED: 'delivered',
  SEEN: 'seen',
  READ: 'read'
};

export const MESSAGE_TYPE = {
  TEXT: 'text',
  IMAGE: 'image',
  VIDEO: 'video',
  FILE: 'file',
  AUDIO: 'audio',
  VOICE: 'voice',
  LOCATION: 'location',
  CONTACT: 'contact'
};

export const CONVERSATION_STATUS = {
  PENDING: 'pending',
  ACTIVE: 'active',
  DECLINED: 'declined',
  BLOCKED: 'blocked'
};

export const SOCKET_EVENTS = {
  // Connection
  CONNECTION: 'connection',
  DISCONNECT: 'disconnect',
  
  // Messages
  MESSAGE: 'message',
  MESSAGE_SENT: 'message-sent',
  MESSAGE_EDITED: 'message_edited',
  MESSAGE_DELETED: 'message_deleted',
  RECEIVE_MESSAGE: 'receive-message',
  
  // Delivery & Read Receipts
  DELIVERED: 'delivered',
  READ_UP_TO: 'read_up_to',
  MESSAGE_SEEN: 'message-seen',
  MESSAGES_READ_RECEIPT: 'messages:read-receipt',
  
  // Typing
  TYPING: 'typing',
  TYPING_STOPPED: 'typing-stopped',
  
  // Presence
  PRESENCE: 'presence',
  USER_STATUS_CHANGED: 'user-status-changed',
  ONLINE_USERS: 'online-users',
  
  // Calls
  CALL_INVITE: 'call:invite',
  CALL_INCOMING: 'call:incoming',
  CALL_RINGING: 'call:ringing',
  CALL_ANSWER: 'call:answer',
  CALL_CANDIDATE: 'call:candidate',
  CALL_HANGUP: 'call:hangup',
  CALL_ENDED: 'call:ended',
  CALL_BUSY: 'call:busy',
  CALL_DECLINED: 'call:declined',
  
  // Legacy call events (for backward compatibility)
  CALL_OFFER: 'call_offer',
  CALL_ANSWER_LEGACY: 'call_answer',
  ICE_CANDIDATE: 'ice_candidate',
  CALL_END: 'call_end',
  
  // Chat requests
  CHAT_REQUEST: 'chat_request',
  CHAT_REQUEST_ACCEPTED: 'chat_request_accepted',
  CHAT_REQUEST_DECLINED: 'chat_request_declined',
  
  // Profile
  USER_PROFILE_UPDATED: 'user_profile_updated'
};

