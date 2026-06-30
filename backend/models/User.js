const mongoose = require("mongoose");

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true
    },
    phone: {
      type: String,
      required: true,
      unique: true,
      trim: true
    },
    password: {
      type: String,
      required: true
    },
    role: {
      type: String,
      enum: ["user", "driver"],
      default: "user"
    },
    isAvailable: {
      type: Boolean,
      default: false
    },
    location: {
      lat: {
        type: Number,
        default: 0
      },
      lng: {
        type: Number,
        default: 0
      }
    }
  },
  { timestamps: true }
);

module.exports = mongoose.model("User", userSchema);
