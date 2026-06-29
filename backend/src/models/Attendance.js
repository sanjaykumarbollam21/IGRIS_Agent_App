const { Sequelize, DataTypes } = require('sequelize');

const Attendance = (sequelize) => {
  const attendanceModel = sequelize.define('Attendance', {
    id: {
      type: DataTypes.UUID,
      defaultValue: Sequelize.UUIDV4,
      primaryKey: true
    },
    userId: {
      type: DataTypes.UUID,
      allowNull: false,
      references: {
        model: 'users',
        key: 'id'
      }
    },
    sessionDate: {
      type: DataTypes.DATEONLY,
      allowNull: false,
      defaultValue: Sequelize.NOW
    },
    sessionTime: {
      type: DataTypes.STRING, // e.g., "09:00 - 09:49"
      allowNull: false
    },
    subject: {
      type: DataTypes.STRING,
      allowNull: false
    },
    status: {
      type: DataTypes.ENUM('Present', 'Absent', 'Late'),
      defaultValue: 'Present'
    },
    markedAt: {
      type: DataTypes.DATE,
      defaultValue: Sequelize.NOW
    }
  }, {
    tableName: 'attendance_records',
    timestamps: true
  });

  attendanceModel.associate = (models) => {
    attendanceModel.belongsTo(models.User, { foreignKey: 'userId', as: 'user' });
  };

  return attendanceModel;
};

module.exports = Attendance;
