'use strict';

const mongoose = require('mongoose');

const userSchema = new mongoose.Schema(
  {
    username: {
      type: String,
      required: [true, 'Username is required'],
      unique: true,
      trim: true,
      minlength: [3, 'Username must be at least 3 characters'],
      maxlength: [50, 'Username cannot exceed 50 characters'],
    },
    email: {
      type: String,
      required: [true, 'Email is required'],
      unique: true,
      lowercase: true,
      trim: true,
      match: [/^\S+@\S+\.\S+$/, 'Please provide a valid email address'],
    },
    full_name: {
      type: String,
      trim: true,
      maxlength: [100, 'Full name cannot exceed 100 characters'],
      default: null,
    },
  },
  {
    timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' },
    versionKey: false,
  }
);

userSchema.set('toJSON', {
  transform: (doc, ret) => {
    ret.id = ret._id.toString();
    delete ret._id;
    return ret;
  },
});

// FIX: Register the model only once using mongoose.models check to prevent
// "Cannot overwrite `User` model once compiled" error
const UserMongoModel = mongoose.models.User || mongoose.model('User', userSchema);

class UserModel {
  static get Model() {
    return UserMongoModel;
  }

  static async findAll({ limit = 50, offset = 0 } = {}) {
    const User = this.Model;
    const [users, total] = await Promise.all([
      User.find().sort({ created_at: 1 }).skip(offset).limit(limit).lean({ virtuals: false }),
      User.countDocuments(),
    ]);
    return {
      users: users.map((u) => ({
        id: u._id.toString(),
        username: u.username,
        email: u.email,
        full_name: u.full_name,
        created_at: u.created_at,
        updated_at: u.updated_at,
      })),
      total,
    };
  }

  static async findById(id) {
    const User = this.Model;
    if (!mongoose.isValidObjectId(id)) return null;
    const u = await User.findById(id).lean();
    if (!u) return null;
    return {
      id: u._id.toString(),
      username: u.username,
      email: u.email,
      full_name: u.full_name,
      created_at: u.created_at,
      updated_at: u.updated_at,
    };
  }

  static async create({ username, email, full_name }) {
    const User = this.Model;
    const u = await User.create({ username, email, full_name: full_name || null });
    return {
      id: u._id.toString(),
      username: u.username,
      email: u.email,
      full_name: u.full_name,
      created_at: u.created_at,
      updated_at: u.updated_at,
    };
  }

  static async update(id, data) {
    const User = this.Model;
    if (!mongoose.isValidObjectId(id)) return null;
    const updates = {};
    if (data.username !== undefined) updates.username = data.username;
    if (data.email !== undefined) updates.email = data.email;
    if (data.full_name !== undefined) updates.full_name = data.full_name;
    if (Object.keys(updates).length === 0) return null;
    const u = await User.findByIdAndUpdate(id, updates, { new: true, runValidators: true }).lean();
    if (!u) return null;
    return {
      id: u._id.toString(),
      username: u.username,
      email: u.email,
      full_name: u.full_name,
      created_at: u.created_at,
      updated_at: u.updated_at,
    };
  }

  static async delete(id) {
    const User = this.Model;
    if (!mongoose.isValidObjectId(id)) return false;
    const result = await User.findByIdAndDelete(id);
    return result !== null;
  }
}

module.exports = UserModel;