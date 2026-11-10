const express = require("express");
const router = express.Router();
const crypto = require("crypto");
const User = require("../models/User");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const authMiddleware = require("../middleware/authMiddleware");

router.post("/register", async (req, res) => {
  try {
    console.log("REGISTER BODY:", req.body);

    const { name, phone, password, role } = req.body;

    if (!name || !phone || !password) {
      return res.status(400).json({
        message: "All fields are required"
      });
    }

    const existingUser = await User.findOne({ phone });

    if (existingUser) {
      return res.status(400).json({
        message: "User already exists"
      });
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const user = new User({
      name,
      phone,
      password: hashedPassword,
      role: role || "user"
    });
    await user.save();

    return res.status(201).json({
      message: "User registered successfully"
    });
  } catch (error) {
    console.log("REGISTER ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
});

router.post("/login", async (req, res) => {
  try {
    const { identifier, password, role } = req.body;

    if (!identifier || !password) {
      return res.status(400).json({
        message: "Username/Phone and password are required"
      });
    }

    const user = await User.findOne({
      $or: [{ name: identifier }, { phone: identifier }]
    });

    if (!user) {
      return res.status(404).json({
        message: "User not found"
      });
    }

    const passwordMatches = await bcrypt.compare(password, user.password);

    if (!passwordMatches) {
      return res.status(401).json({
        message: "Invalid password"
      });
    }

    if (role === "driver" && user.role !== "driver") {
      return res.status(403).json({
        message: "This account is not a driver account"
      });
    }

    // Generate unique sessionId using crypto.randomUUID()
    const sessionId = crypto.randomUUID();

    const token = jwt.sign(
      { id: user._id, role: user.role, sessionId },
      process.env.JWT_SECRET || "secretkey",
      { expiresIn: "7d" }
    );

    user.activeSessionId = sessionId;
    user.active_session_token = token;
    await user.save();

    // Real-Time Kick via Socket.io
    const io = req.app.get("io");
    if (io) {
      const kickPayload = {
        userId: user._id.toString(),
        newSessionId: sessionId,
        message: "Your account was logged in on another device."
      };

      const userRoom = `user_${user._id}`;
      // Emit force_logout & session_replaced to the user room
      io.to(userRoom).emit("force_logout", kickPayload);
      io.to(userRoom).emit("session_replaced", kickPayload);

      // Force disconnect any socket whose sessionId does not match newSessionId
      try {
        const sockets = await io.in(userRoom).fetchSockets();
        for (const s of sockets) {
          if (s.sessionId && s.sessionId !== sessionId) {
            console.log(`[AUTH] Disconnecting stale session socket ${s.id} for user ${user._id}`);
            s.emit("force_logout", kickPayload);
            s.emit("session_replaced", kickPayload);
            s.disconnect(true);
          }
        }
      } catch (err) {
        console.log("[AUTH] Error checking user room sockets:", err.message);
      }

      if (user.activeSocketId) {
        io.to(user.activeSocketId).emit("force_logout", kickPayload);
        io.to(user.activeSocketId).emit("session_replaced", kickPayload);
      }
    }

    return res.status(200).json({
      message: "Login successful",
      token,
      sessionId,
      userId: user._id,
      role: user.role,
      isAvailable: user.isAvailable || false,
      name: user.name,
      phone: user.phone
    });
  } catch (error) {
    console.log("LOGIN ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
});

router.post("/logout", authMiddleware, async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ success: false, message: "User not found" });
    }

    // Only clear activeSessionId if requester's sessionId matches current activeSessionId
    if (!req.user.sessionId || req.user.sessionId === user.activeSessionId) {
      user.activeSessionId = null;
      user.activeSocketId = null;
      user.active_session_token = null;
      await user.save();
    }

    const io = req.app.get("io");
    if (io) {
      try {
        const userRoom = `user_${user._id}`;
        const sockets = await io.in(userRoom).fetchSockets();
        for (const s of sockets) {
          if (s.sessionId === req.user.sessionId) {
            s.leave(userRoom);
            s.disconnect(true);
          }
        }
      } catch (_) {}
    }

    return res.status(200).json({
      success: true,
      message: "Logged out successfully"
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
});

const driverController = require("../controllers/driverController");

router.post("/drivers-list", authMiddleware, driverController.getDrivers);

router.get("/profile", authMiddleware, async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }
    return res.status(200).json({
      name: user.name,
      phone: user.phone,
      role: user.role
    });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
});

router.post("/location", authMiddleware, async (req, res) => {
  try {
    const { lat, lng } = req.body;
    if (lat === undefined || lng === undefined) {
      return res.status(400).json({ message: "Latitude and longitude are required" });
    }
    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }
    user.location = { lat: Number(lat), lng: Number(lng) };
    await user.save();

    const io = req.app.get("io");
    if (io) {
      io.emit("driverLocationUpdated", {
        driverId: user._id,
        lat: Number(lat),
        lng: Number(lng)
      });
    }

    return res.status(200).json({ message: "Location updated successfully" });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
});

module.exports = router;

