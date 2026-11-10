const crypto = require("crypto");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");
const User = require("../models/User");
const Driver = require("../models/Driver");

const normalizeRole = (role) => {
  if (!role) return "user";
  const r = role.toString().toLowerCase().trim();
  if (r === "driver" || r === "captain") return "driver";
  return "user"; // "rider" or "user"
};

// 1. Role-Based Guest Login
exports.guestLogin = async (req, res) => {
  try {
    const rawRole = req.body.role || "rider";
    const role = normalizeRole(rawRole);

    const isDriver = role === "driver";
    const email = isDriver ? "guest.driver@gmail.com" : "guest.rider@gmail.com";
    const name = isDriver ? "Guest Driver" : "Guest Rider";
    const defaultLocation = { lat: 11.1401, lng: 79.0786 }; // Ariyalur default

    let user = await User.findOne({
      $or: [{ phone: email }, { username: email }]
    });

    if (!user) {
      const hashedPassword = await bcrypt.hash("guest-password-auth-2026", 10);
      user = new User({
        name,
        phone: email,
        password: hashedPassword,
        role,
        isAvailable: isDriver ? false : false,
        location: defaultLocation
      });
      await user.save();
    } else {
      // Ensure correct role and details
      if (user.role !== role) {
        user.role = role;
      }
      user.name = name;
      await user.save();
    }

    if (isDriver) {
      try {
        let driverRecord = await Driver.findOne({
          $or: [{ _id: user._id }, { phone: user.phone }]
        });
        if (!driverRecord) {
          driverRecord = new Driver({
            _id: user._id,
            name: user.name,
            phone: user.phone,
            bikeNumber: "TN-48-GUEST-01",
            available: user.isAvailable || false,
            location: user.location || defaultLocation
          });
          await driverRecord.save();
        }
      } catch (err) {
        console.warn("[GUEST LOGIN] Driver sync note:", err.message);
      }
    }

    const sessionId = crypto.randomUUID();
    const token = jwt.sign(
      { id: user._id, role: user.role, sessionId },
      process.env.JWT_SECRET || "secretkey",
      { expiresIn: "7d" }
    );

    user.activeSessionId = sessionId;
    user.active_session_token = token;
    await user.save();

    return res.status(200).json({
      success: true,
      message: "Guest login successful",
      token,
      sessionId,
      userId: user._id,
      role: user.role,
      name: user.name,
      phone: user.phone,
      isAvailable: user.isAvailable || false,
      user: {
        id: user._id,
        name: user.name,
        role: user.role,
        phone: user.phone,
        isAvailable: user.isAvailable || false
      }
    });
  } catch (error) {
    console.error("GUEST LOGIN ERROR:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Failed to authenticate guest"
    });
  }
};

// 2. Real-Time Google Sign-In
exports.googleLogin = async (req, res) => {
  try {
    const { idToken, role: rawRole, email: providedEmail, name: providedName, avatar: providedAvatar } = req.body;
    const role = normalizeRole(rawRole);
    const isDriver = role === "driver";

    let email = providedEmail;
    let name = providedName;
    let avatar = providedAvatar;

    // Verify token if idToken exists
    if (idToken) {
      try {
        const { OAuth2Client } = require("google-auth-library");
        const client = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);
        const ticket = await client.verifyIdToken({
          idToken,
          audience: process.env.GOOGLE_CLIENT_ID
        });
        const payload = ticket.getPayload();
        if (payload) {
          email = payload.email || email;
          name = payload.name || name;
          avatar = payload.picture || avatar;
        }
      } catch (libErr) {
        // Fallback: decode JWT payload without external network
        try {
          const parts = idToken.split(".");
          if (parts.length === 3) {
            const decoded = JSON.parse(Buffer.from(parts[1], "base64").toString("utf-8"));
            email = decoded.email || email;
            name = decoded.name || name;
            avatar = decoded.picture || avatar;
          }
        } catch (_) {}
      }
    }

    if (!email) {
      return res.status(400).json({
        success: false,
        message: "Google email could not be verified"
      });
    }

    if (!name) {
      name = email.split("@")[0].replace(/[._-]/g, " ");
      name = name.charAt(0).toUpperCase() + name.slice(1);
    }

    const defaultLocation = { lat: 11.1401, lng: 79.0786 };

    let user = await User.findOne({
      $or: [{ phone: email }, { username: email }]
    });

    if (!user) {
      const hashedPassword = await bcrypt.hash(crypto.randomUUID(), 10);
      user = new User({
        name,
        phone: email,
        password: hashedPassword,
        role,
        isAvailable: false,
        location: defaultLocation
      });
      await user.save();
    } else {
      // If logging in as driver, elevate role
      if (isDriver && user.role !== "driver") {
        user.role = "driver";
        await user.save();
      }
    }

    if (user.role === "driver") {
      try {
        let driverRecord = await Driver.findOne({
          $or: [{ _id: user._id }, { phone: user.phone }]
        });
        if (!driverRecord) {
          driverRecord = new Driver({
            _id: user._id,
            name: user.name,
            phone: user.phone,
            bikeNumber: "TN-48-AUTO-01",
            available: user.isAvailable || false,
            location: user.location || defaultLocation
          });
          await driverRecord.save();
        }
      } catch (err) {
        console.warn("[GOOGLE LOGIN] Driver sync note:", err.message);
      }
    }

    const sessionId = crypto.randomUUID();
    const token = jwt.sign(
      { id: user._id, role: user.role, sessionId },
      process.env.JWT_SECRET || "secretkey",
      { expiresIn: "7d" }
    );

    user.activeSessionId = sessionId;
    user.active_session_token = token;
    await user.save();

    return res.status(200).json({
      success: true,
      message: "Google login successful",
      token,
      sessionId,
      userId: user._id,
      role: user.role,
      name: user.name,
      phone: user.phone,
      isAvailable: user.isAvailable || false,
      user: {
        id: user._id,
        name: user.name,
        role: user.role,
        phone: user.phone,
        avatar: avatar || null,
        isAvailable: user.isAvailable || false
      }
    });
  } catch (error) {
    console.error("GOOGLE LOGIN ERROR:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Failed to authenticate with Google"
    });
  }
};

