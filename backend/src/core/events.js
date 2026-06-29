/**
 * Centralized Event Constants
 * Freezing the object prevents typos and accidental modifications.
 */
const EVENTS = Object.freeze({
  // Tool Execution Events
  TOOL_EXECUTED: 'tool.executed',
  TOOL_ERROR: 'tool.error',

  // Knowledge / RAG Events
  DOCUMENT_INGESTED: 'document.ingested',
  DOCUMENT_DELETED: 'document.deleted',
  KNOWLEDGE_SEARCHED: 'knowledge.searched',

  // User / Auth Events
  USER_REGISTERED: 'user.registered',
  USER_LOGIN: 'user.login',
  USER_UPDATED: 'user.updated',

  // Conversation Events
  MESSAGE_RECEIVED: 'message.received',
  AGENT_RESPONDED: 'agent.responded',

  // System Events
  SYSTEM_READY: 'system.ready',
  SYSTEM_ERROR: 'system.error',
  CIRCUIT_OPENED: 'circuit.opened',
  CIRCUIT_CLOSED: 'circuit.closed',
  CIRCUIT_HALF_OPEN: 'circuit.halfOpen',
});

module.exports = { EVENTS };
