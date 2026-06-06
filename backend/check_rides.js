const mongoose = require("mongoose");
require("dotenv").config();
const Ride = require("./models/Ride");

mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/biketaxi")
.then(async () => {
  console.log("Connected to MongoDB");
  const rides = await Ride.find({}).lean();
  console.log("ALL RIDES IN DATABASE:");
  rides.forEach(r => {
    console.log({
      id: r._id,
      status: r.status,
      negotiationStatus: r.negotiationStatus,
      negotiationExpiresAt: r.negotiationExpiresAt,
      now: new Date(),
      expired: r.negotiationExpiresAt ? r.negotiationExpiresAt <= new Date() : false,
      offersCount: r.offers ? r.offers.length : 0,
      offers: r.offers
    });
  });
  mongoose.connection.close();
})
.catch(err => {
  console.error(err);
});
