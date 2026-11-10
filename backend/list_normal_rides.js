const mongoose = require("mongoose");
require("dotenv").config();
const Ride = require("./models/Ride");

const mongoUri = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/biketaxi";

mongoose.connect(mongoUri)
.then(async () => {
  console.log("Connected to MongoDB");
  const rides = await Ride.find({ bookingMode: "normal" }).sort({ createdAt: -1 }).limit(5).lean();
  console.log("RECENT NORMAL RIDES:");
  rides.forEach(r => {
    console.log({
      id: r._id,
      status: r.status,
      driverId: r.driverId,
      pickup: r.pickup,
      destination: r.destination,
      createdAt: r.createdAt
    });
  });
  mongoose.connection.close();
})
.catch(err => {
  console.error("Query error:", err);
});
