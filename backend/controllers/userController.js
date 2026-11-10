const User = require("../models/User");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");

exports.registerUser = async (req, res) => {
  try {
    const { username, name, phone, password, role } = req.body;

    if (!username && !phone) {
      return res.status(400).json({ message: "Username or Phone number is required" });
    }

    const existingUser = await User.findOne({
      $or: [
        ...(username ? [{ username }] : []),
        ...(phone ? [{ phone }] : [])
      ]
    });
    if (existingUser) {
      return res.status(400).json({ message: "User already exists" });
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const user = new User({
      username,
      name,
      phone,
      password: hashedPassword,
      role: role || "user"
    });

    await user.save();

    res.json({ message: "User registered" });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.loginUser = async (req, res) => {
  try {
    const { identifier, password, role } = req.body;

    if (!identifier) {
      return res.status(400).json({ message: "Username or Phone number is required" });
    }

    const user = await User.findOne({
      $or: [{ username: identifier }, { phone: identifier }, { name: identifier }]
    });

    if (!user) {
      return res.status(404).json({ message: "User not found" });
    }

    const match = await bcrypt.compare(password, user.password);

    if (!match) {
      return res.status(401).json({ message: "Invalid password" });
    }

    if (role === "driver" && user.role !== "driver") {
      return res.status(403).json({ message: "This account is not a driver account" });
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
      io.to(userRoom).emit("force_logout", kickPayload);
      io.to(userRoom).emit("session_replaced", kickPayload);

      try {
        const sockets = await io.in(userRoom).fetchSockets();
        for (const s of sockets) {
          if (s.sessionId && s.sessionId !== sessionId) {
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

    res.status(200).json({
      message: "Login successful",
      token,
      sessionId,
      userId: user._id,
      role: user.role,
      isAvailable: user.isAvailable || false,
      name: user.name,
      phone: user.phone,
      user: {
        id: user._id,
        name: user.name,
        role: user.role
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.logoutUser = async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ success: false, message: "User not found" });
    }

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
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
};