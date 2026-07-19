const express = require("express");
const mongoose = require("mongoose");
const http = require("http");
const path = require("path");
const { Server } = require("socket.io");
require("dotenv").config();
const rideController = require("./controllers/rideController");
const ridesRoutes = require("./routes/rideRoutes");
const userRoutes = require("./routes/userRoutes");
const driverRoutes = require("./routes/driverRoutes");
const fareRoutes = require("./routes/fareRoutes");
const adminFareRoutes = require("./routes/adminFareRoutes");
const receiptRoutes = require("./routes/receiptRoutes");
const cors = require("cors");

const app = express();

app.use(cors({
  origin: true,
  credentials: true
}));
app.use(express.json());

/* ---------------- DATABASE ---------------- */

mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/biketaxi")
.then(()=>{
    console.log("MongoDB Connected");
})
.catch((err)=>{
    console.log(err);
});

/* ---------------- HEALTH CHECK ---------------- */

app.get("/api/health", (req, res) => {
  res.json({
    status: "ok",
    db: mongoose.connection.readyState === 1 ? "connected" : "disconnected",
    uptime: process.uptime()
  });
});

app.get("/api/cleanup-rides", async (req, res) => {
  try {
    const Ride = require("./models/Ride");
    const User = require("./models/User");
    const result = await Ride.updateMany(
      { status: { $in: ["requested", "negotiating", "accepted", "ongoing"] } },
      { $set: { status: "cancelled", negotiationStatus: "rejected", negotiationExpiresAt: null } }
    );
    await User.updateMany(
      { role: "driver" },
      { $set: { isAvailable: false } }
    );
    res.json({
      message: "Database cleanup completed successfully.",
      cancelledRidesCount: result.modifiedCount
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/list-normal-rides", async (req, res) => {
  try {
    const Ride = require("./models/Ride");
    const rides = await Ride.find({ bookingMode: "normal" }).sort({ createdAt: -1 }).limit(10).lean();
    res.json({ rides });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/* ---------------- ROUTES ---------------- */

app.use("/api/users",userRoutes);
app.use("/api/rides", ridesRoutes);
app.use("/api/drivers",driverRoutes);
app.use("/api/fare", fareRoutes);
app.use("/api/admin/fare", adminFareRoutes);
app.use("/api/receipts", receiptRoutes);

/* ---------------- SOCKET SERVER ---------------- */

const server = http.createServer(app);

const io = new Server(server, {
  cors: {
    origin: "*"
  }
});

app.set("io", io);

app.use(express.json());

io.on("connection", (socket) => {
  console.log("User connected:", socket.id);
});

setInterval(async () => {
  try {
    await rideController.expireOpenNegotiations(io);
    await rideController.expireRequestedRides(io);
  } catch (error) {
    console.log("SWEEP ERROR:", error.message);
  }
}, 10000);

/* ---------------- STATIC FRONTEND ---------------- */

const frontendBuildPath = path.join(__dirname, "../frontend/bike_taxi_app/build/web");
app.use(express.static(frontendBuildPath));

app.get(/^(?!\/api).*/, (req, res) => {
  res.sendFile(path.join(frontendBuildPath, "index.html"));
});

/* ---------------- START SERVER ---------------- */

const PORT = process.env.PORT || 5000;

server.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on port ${PORT}`);
});
