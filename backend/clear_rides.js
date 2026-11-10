const mongoose = require("mongoose");
require("dotenv").config();
const Ride = require("./models/Ride");
const User = require("./models/User");

const mongoUri = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/biketaxi";

mongoose.connect(mongoUri)
.then(async () => {
  console.log("Connected to MongoDB for cleanup");
  
  // Update all active/pending rides to cancelled
  const result = await Ride.updateMany(
    { status: { $in: ["requested", "negotiating", "accepted", "ongoing"] } },
    { $set: { status: "cancelled", negotiationStatus: "rejected", negotiationExpiresAt: null } }
  );
  
  console.log(`Cancelled ${result.modifiedCount} active/stale rides.`);

  // Reset all drivers to be available (online)
  const driverResult = await User.updateMany(
    { role: "driver" },
    { $set: { isAvailable: true } }
  );
  console.log(`Reset ${driverResult.modifiedCount} drivers to available status.`);

  mongoose.connection.close();
})
.catch(err => {
  console.error("Cleanup error:", err);
});
