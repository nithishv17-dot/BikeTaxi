const mongoose = require("mongoose");

const rideSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true
    },
    driverId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null
    },
    pickup: {
      type: String,
      required: true,
      trim: true
    },
    destination: {
      type: String,
      required: true,
      trim: true
    },
    status: {
      type: String,
      enum: ["requested", "accepted", "ongoing", "completed", "cancelled"],
      default: "requested"
    }
  },
  { timestamps: true }
);

module.exports = mongoose.model("Ride", rideSchema);