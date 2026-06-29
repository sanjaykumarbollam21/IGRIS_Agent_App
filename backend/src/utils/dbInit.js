const db = require('../models');
const { sequelize, User, ToolUsage, Automation, UserSettings, Conversation, KnowledgeDocument, KnowledgeChunk, Attendance, CallSummary, WorkflowExecution } = db;

const initializeDatabase = async () => {
  try {
    console.log('Initializing database...');
    await sequelize.authenticate();
    console.log('Database connection established successfully.');

    const isSqlite = sequelize.options.dialect === 'sqlite';
    if (isSqlite) {
      await sequelize.query('PRAGMA foreign_keys = OFF');
    }

    // 1. No-dependency tables first
    await User.sync({ alter: true });
    console.log('User table synchronized.');

    // 2. Tables that reference User
    if (ToolUsage) {
      await ToolUsage.sync({ alter: true });
      console.log('ToolUsage table synchronized.');
    }
    if (Automation) {
      await Automation.sync({ alter: true });
      console.log('Automation table synchronized.');
    }
    if (UserSettings) {
      await UserSettings.sync({ alter: true });
      console.log('UserSettings table synchronized.');
    }
    if (Conversation) {
      await Conversation.sync({ alter: true });
      console.log('Conversation table synchronized.');
    }
    if (KnowledgeDocument) {
      await KnowledgeDocument.sync({ alter: true });
      console.log('KnowledgeDocument table synchronized.');
    }
    if (KnowledgeChunk) {
      await KnowledgeChunk.sync({ alter: true });
      console.log('KnowledgeChunk table synchronized.');
    }
    if (Attendance) {
      await Attendance.sync({ alter: true });
      console.log('Attendance table synchronized.');
    }
    if (CallSummary) {
      await CallSummary.sync({ alter: true });
      console.log('CallSummary table synchronized.');
    }
    if (WorkflowExecution) {
      await WorkflowExecution.sync({ alter: true });
      console.log('WorkflowExecution table synchronized.');
    }

    if (isSqlite) {
      await sequelize.query('PRAGMA foreign_keys = ON');
    }

    console.log('All models synchronized successfully.');

    // Create default admin user if none exists
    const adminExists = await User.findOne({ where: { email: 'admin@igris.ai' } });
    if (!adminExists) {
      await User.create({
        email: 'admin@igris.ai',
        password: 'Admin123!',
        firstName: 'Admin',
        lastName: 'User',
        isActive: true,
        isEmailVerified: true,
      });
      console.log('Default admin user created.');
    }

    console.log('Database initialization completed successfully.');
    return true;
  } catch (error) {
    console.error('Error initializing database:', error.stack || error.message);
    if (error.errors) {
      console.error('Detailed validation errors:', error.errors.map(e => ({
        message: e.message,
        type: e.type,
        path: e.path,
        value: e.value
      })));
    }
    throw error;
  }
};

module.exports = { initializeDatabase };