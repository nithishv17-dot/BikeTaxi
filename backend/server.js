const dns = require("dns");
dns.setServers(["8.8.8.8", "1.1.1.1"]);

const express = require("express");
const mongoose = require("mongoose");
const http = require("http");
const path = require("path");
const fs = require("fs");
const { Server } = require("socket.io");
const jwt = require("jsonwebtoken");
require("dotenv").config();
const User = require("./models/User");
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

const mongoUri = process.env.MONGODB_URI || process.env.MONGO_URI;

if (!mongoUri) {
  console.error("CRITICAL: Neither MONGODB_URI nor MONGO_URI is defined!");
  process.exit(1);
}

const maskedUri = mongoUri.replace(/\/\/([^:]+):([^@]+)@/, "//***:***@");
console.log(`[DATABASE] Connecting to: ${maskedUri}`);

mongoose
  .connect(mongoUri, {
    serverSelectionTimeoutMS: 5000,
  })
  .then((conn) => {
    console.log(`[DATABASE] MongoDB Connected successfully to host: ${conn.connection.host}`);
  })
  .catch((err) => {
    console.error("[DATABASE] MongoDB connection error:", err.message);
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

const authRoutes = require("./routes/authRoutes");

app.use("/api/auth", authRoutes);
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

io.use((socket, next) => {
  try {
    const auth = socket.handshake.auth || {};
    const query = socket.handshake.query || {};
    const token = auth.token || query.token;
    const sessionId = auth.sessionId || query.sessionId;
    const userId = auth.userId || query.userId;

    if (token) {
      try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || "secretkey");
        socket.userId = decoded.id ? decoded.id.toString() : null;
        socket.sessionId = decoded.sessionId || sessionId;
      } catch (err) {
        console.log(`[SOCKET] Handshake token verify note: ${err.message}`);
      }
    }
    if (userId && !socket.userId) {
      socket.userId = userId.toString();
    }
    if (sessionId && !socket.sessionId) {
      socket.sessionId = sessionId.toString();
    }
    next();
  } catch (err) {
    next();
  }
});

io.on("connection", async (socket) => {
  console.log("User connected:", socket.id);

  const bindUserRoom = async (userId, sessionId) => {
    if (!userId) return;
    const uidStr = userId.toString();
    socket.userId = uidStr;
    if (sessionId) {
      socket.sessionId = sessionId.toString();
    }
    const room = `user_${uidStr}`;
    socket.join(room);
    socket.join(`driver_${uidStr}`);
    console.log(`[SOCKET] Socket ${socket.id} joined room ${room} and driver_${uidStr} (sessionId: ${socket.sessionId || "none"})`);

    try {
      await User.findByIdAndUpdate(uidStr, { activeSocketId: socket.id });
    } catch (e) {
      console.log("[SOCKET] Error updating activeSocketId:", e.message);
    }
  };

  if (socket.userId) {
    await bindUserRoom(socket.userId, socket.sessionId);
  }

  socket.on("authenticate", async (data) => {
    try {
      let userId = data?.userId;
      let sessionId = data?.sessionId;
      const token = data?.token;
      if (token) {
        try {
          const decoded = jwt.verify(token, process.env.JWT_SECRET || "secretkey");
          userId = decoded.id;
          sessionId = decoded.sessionId || sessionId;
        } catch (e) {
          console.log("[SOCKET] Auth token verify error:", e.message);
        }
      }
      if (userId) {
        await bindUserRoom(userId, sessionId);
        socket.emit("authenticated", { success: true, userId, sessionId });
      }
    } catch (err) {
      console.log("[SOCKET] Authenticate handler error:", err.message);
    }
  });

  socket.on("join_user_room", async (data) => {
    const userId = data?.userId;
    const sessionId = data?.sessionId;
    if (userId) {
      await bindUserRoom(userId, sessionId);
    }
  });

  socket.on("driver_online", async (data) => {
    try {
      const driverId = data?.driverId || socket.userId;
      const lat = Number(data?.lat ?? data?.location?.lat);
      const lng = Number(data?.lng ?? data?.location?.lng);
      console.log(`[SOCKET] driver_online received for driverId: ${driverId}, coords: (${lat}, ${lng})`);

      socket.join("active_drivers");
      socket.isDriver = true;
      if (driverId) {
        socket.driverId = driverId.toString();

        const updateData = { isAvailable: true };
        if (Number.isFinite(lat) && Number.isFinite(lng) && !(lat === 0 && lng === 0)) {
          updateData.location = { lat, lng };
        }
        const updatedDriver = await User.findByIdAndUpdate(
          driverId,
          { $set: updateData },
          { new: true }
        ).select("name phone role isAvailable location");

        try {
          const Driver = require("./models/Driver");
          await Driver.findOneAndUpdate(
            { $or: [{ _id: driverId }, { phone: updatedDriver?.phone }] },
            {
              $set: {
                available: true,
                ...(updateData.location ? { location: updateData.location } : {})
              }
            }
          );
        } catch (_) {}

        io.emit("driver_status_changed", {
          driverId: driverId.toString(),
          isAvailable: true,
          location: updateData.location || updatedDriver?.location
        });

        if (updateData.location) {
          io.emit("driverLocationUpdated", {
            driverId: driverId.toString(),
            lat: updateData.location.lat,
            lng: updateData.location.lng
          });
        }
      }
    } catch (e) {
      console.log("[SOCKET] driver_online error:", e.message);
    }
  });

  socket.on("driver_offline", async (data) => {
    try {
      const driverId = data?.driverId || socket.driverId || socket.userId;
      console.log(`[SOCKET] driver_offline received for driverId: ${driverId}`);
      socket.leave("active_drivers");
      if (driverId) {
        await User.findByIdAndUpdate(driverId, { $set: { isAvailable: false } });
        try {
          const Driver = require("./models/Driver");
          await Driver.findOneAndUpdate(
            { $or: [{ _id: driverId }, { phone: (await User.findById(driverId))?.phone }] },
            { $set: { available: false } }
          );
        } catch (_) {}

        io.emit("driver_status_changed", {
          driverId: driverId.toString(),
          isAvailable: false
        });
      }
    } catch (e) {
      console.log("[SOCKET] driver_offline error:", e.message);
    }
  });

  socket.on("driver_location_update", async (data) => {
    try {
      const driverId = data?.driverId || socket.driverId || socket.userId;
      const lat = Number(data?.lat ?? data?.location?.lat);
      const lng = Number(data?.lng ?? data?.location?.lng);

      if (driverId && Number.isFinite(lat) && Number.isFinite(lng) && !(lat === 0 && lng === 0)) {
        await User.findByIdAndUpdate(driverId, {
          $set: { location: { lat, lng } }
        });

        try {
          const Driver = require("./models/Driver");
          await Driver.findOneAndUpdate(
            { $or: [{ _id: driverId }, { phone: (await User.findById(driverId))?.phone }] },
            { $set: { location: { lat, lng } } }
          );
        } catch (_) {}

        io.emit("driverLocationUpdated", {
          driverId: driverId.toString(),
          lat,
          lng
        });
      }
    } catch (e) {
      console.log("[SOCKET] driver_location_update error:", e.message);
    }
  });

  socket.on("join_ride", (data) => {
    const rideId = typeof data === "string" ? data : data?.rideId;
    if (rideId) {
      socket.join(`ride_${rideId}`);
      console.log(`[SOCKET] ${socket.id} joined ride_${rideId}`);
    }
  });

  socket.on("update_rider_location", (data) => {
    const rideId = data?.rideId;
    const lat = Number(data?.lat);
    const lng = Number(data?.lng);
    if (!rideId || !Number.isFinite(lat) || !Number.isFinite(lng)) return;
    io.to(`ride_${rideId}`).emit("rider_location_updated", { rideId, lat, lng });
  });

  socket.on("update_driver_location", (data) => {
    const rideId = data?.rideId;
    const driverId = (data?.driverId || socket.driverId || socket.userId)?.toString();
    const lat = Number(data?.lat);
    const lng = Number(data?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    if (rideId) {
      io.to(`ride_${rideId}`).emit("driver_location_updated", { rideId, driverId, lat, lng });
    }
    if (driverId) {
      io.emit("driverLocationUpdated", { driverId, lat, lng });
    }
  });

  socket.on("disconnect", async () => {
    console.log("User disconnected:", socket.id);
    if (socket.userId) {
      try {
        await User.updateOne(
          { _id: socket.userId, activeSocketId: socket.id },
          { $set: { activeSocketId: null } }
        );
      } catch (_) {}
    }
  });
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

const reactDist = path.join(__dirname, "../frontend/react_app/dist");
const flutterDist = path.join(__dirname, "../frontend/bike_taxi_app/build/web");
const frontendBuildPath = fs.existsSync(reactDist) ? reactDist : flutterDist;

app.use(express.static(frontendBuildPath));

app.get(/^(?!\/api).*/, (req, res) => {
  res.sendFile(path.join(frontendBuildPath, "index.html"));
});

/* ---------------- START SERVER ---------------- */

const PORT = process.env.PORT || 5000;

server.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on port ${PORT}`);
});
