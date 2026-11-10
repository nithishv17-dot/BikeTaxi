const mongoose = require("mongoose");

const rideOfferSchema = new mongoose.Schema(
  {
    driverId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true
    },
    driverName: {
      type: String,
      required: true,
      trim: true
    },
    driverPhone: {
      type: String,
      default: "",
      trim: true
    },
    offeredFare: {
      type: Number,
      required: true
    },
    status: {
      type: String,
      enum: ["pending", "selected", "rejected", "accepted_base"],
      default: "pending"
    }
  },
  { timestamps: true, _id: true }
);

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
    pickupAddress: {
      type: String,
      required: true,
      trim: true
    },
    pickupLat: {
      type: Number,
      required: true
    },
    pickupLng: {
      type: Number,
      required: true
    },
    pickupPlaceId: {
      type: String,
      trim: true,
      default: ""
    },
    destination: {
      type: String,
      required: true,
      trim: true
    },
    dropAddress: {
      type: String,
      required: true,
      trim: true
    },
    dropLat: {
      type: Number,
      required: true
    },
    dropLng: {
      type: Number,
      required: true
    },
    dropPlaceId: {
      type: String,
      trim: true,
      default: ""
    },
    paymentMethod: {
      type: String,
      enum: ["Cash", "UPI", "Card"],
      default: "Cash"
    },
    paymentStatus: {
      type: String,
      enum: ["Pending", "Paid"],
      default: "Pending"
    },
    bookingMode: {
      type: String,
      enum: ["normal", "negotiation"],
      default: "normal"
    },
    estimatedFare: {
      type: Number,
      default: 0
    },
    finalFare: {
      type: Number,
      default: 0
    },
    initialFare: {
      type: Number,
      default: 0
    },
    offeredFare: {
      type: Number,
      default: 0
    },
    negotiationStatus: {
      type: String,
      enum: [
        "none",
        "open",
        "countered",
        "accepted",
        "rejected",
        "negotiation_expired"
      ],
      default: "none"
    },
    negotiationExpiresAt: {
      type: Date,
      default: null
    },
    offers: {
      type: [rideOfferSchema],
      default: []
    },
    status: {
      type: String,
      enum: [
        "requested",
        "negotiating",
        "accepted",
        "ongoing",
        "completed",
        "cancelled",
        "negotiation_expired"
      ],
      default: "requested"
    },
    otp: {
      type: String,
      default: ""
    }
  },
  { timestamps: true }
);

module.exports = mongoose.model("Ride", rideSchema);
