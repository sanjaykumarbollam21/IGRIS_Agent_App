const { Sequelize, DataTypes } = require('sequelize');
const bcrypt = require('bcryptjs');

const User = (sequelize) => {
  const userModel = sequelize.define('User', {
    id: {
      type: DataTypes.UUID,
      defaultValue: Sequelize.UUIDV4,
      primaryKey: true
    },
    email: {
      type: DataTypes.STRING,
      allowNull: false,
      unique: true,
      validate: {
        isEmail: true
      }
    },
    password: {
      type: DataTypes.STRING,
      allowNull: false
    },
    firstName: {
      type: DataTypes.STRING,
      allowNull: false
    },
    lastName: {
      type: DataTypes.STRING,
      allowNull: false
    },
    phoneNumber: {
      type: DataTypes.STRING,
      allowNull: true
    },
    dateOfBirth: {
      type: DataTypes.DATEONLY,
      allowNull: true
    },
    geminiApiKey: {
      type: DataTypes.STRING,
      allowNull: true
    },
    murfApiKey: {
      type: DataTypes.STRING,
      allowNull: true
    },
    telegramId: {
      type: DataTypes.BIGINT,
      allowNull: true,
      unique: true
    },
    telegramChatId: {
      type: DataTypes.STRING,
      allowNull: true
    },
    myniatUsername: {
      type: DataTypes.STRING,
      allowNull: true
    },
    myniatPassword: {
      type: DataTypes.STRING,
      allowNull: true
    },
    collegeWifiSsids: {
      type: DataTypes.TEXT, // Store as JSON string
      allowNull: true
    },
    isActive: {
      type: DataTypes.BOOLEAN,
      defaultValue: true
    },
    isEmailVerified: {
      type: DataTypes.BOOLEAN,
      defaultValue: false
    },
    emailVerificationToken: {
      type: DataTypes.STRING,
      allowNull: true
    },
    emailVerificationTokenExpiresAt: {
      type: DataTypes.DATE,
      allowNull: true
    },
    passwordResetToken: {
      type: DataTypes.STRING,
      allowNull: true
    },
    passwordResetTokenExpiresAt: {
      type: DataTypes.DATE,
      allowNull: true
    },
    lastLoginAt: {
      type: DataTypes.DATE,
      allowNull: true
    },
    createdAt: {
      type: DataTypes.DATE,
      defaultValue: Sequelize.NOW
    },
    updatedAt: {
      type: DataTypes.DATE,
      defaultValue: Sequelize.NOW
    }
  }, {
    tableName: 'users',
    timestamps: true,
    hooks: {
      beforeCreate: async (user) => {
        if (user.password) {
          const salt = await bcrypt.genSalt(12);
          user.password = await bcrypt.hash(user.password, salt);
        }
      },
      beforeUpdate: async (user) => {
        if (user.changed('password')) {
          const salt = await bcrypt.genSalt(12);
          user.password = await bcrypt.hash(user.password, salt);
        }
      }
    }
  });

  // Instance methods
  userModel.prototype.comparePassword = async function(candidatePassword) {
    return bcrypt.compare(candidatePassword, this.password);
  };

  userModel.prototype.toJSON = function() {
    const values = { ...this.get() };
    delete values.password;
    delete values.geminiApiKey;
    delete values.murfApiKey;
    delete values.myniatPassword;
    return values;
  };

  // Static methods
  userModel.findByLogin = async (login) => {
    let user = await userModel.findOne({ where: { email: login } });

    if (!user) {
      user = await userModel.findOne({ where: { phoneNumber: login } });
    }

    return user;
  };

  return userModel;
};

// Associations
User.associate = (models) => {
  // This is actually used by the loader in index.js,
  // but since User is a function, the association must be handled
  // inside the function or via the returned model.
  // The index.js loader handles this.
};

module.exports = User;
