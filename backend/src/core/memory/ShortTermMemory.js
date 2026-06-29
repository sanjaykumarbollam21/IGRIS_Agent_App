/**
 * ShortTermMemory
 * Manages the immediate conversational context window (recent messages, active tool results).
 */
class ShortTermMemory {
  constructor(models, container) {
    this.conversationRepository = container.resolve('conversationRepository');
    this.toolUsageRepository = container.resolve('toolUsageRepository');
  }

  async retrieve(userId, sessionId) {
    const messages = await this.conversationRepository.findBySession(userId, sessionId);
    const tools = await this.toolUsageRepository.findRecentLastHour(userId);

    // Keep only the last 20 messages for short-term window
    const recentMessages = messages.slice(-20).map(m => ({
      role: m.role,
      content: m.content
    }));

    return {
      messages: recentMessages,
      tools: tools.map(t => ({ tool: t.toolName, result: t.result }))
    };
  }
}

module.exports = ShortTermMemory;
