const express = require("express");
const router = express.Router();
const User = require("../models/User");
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

    const user = new User({ name, phone, password, role: role || "user" });
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
    const { phone, password, role } = req.body;

    if (!phone || !password) {
      return res.status(400).json({
        message: "Phone and password are required"
      });
    }

    const user = await User.findOne({ phone });

    if (!user) {
      return res.status(404).json({
        message: "User not found"
      });
    }

    if (user.password !== password) {
      return res.status(401).json({
        message: "Invalid password"
      });
    }

    if (role === "driver" && user.role !== "driver") {
      return res.status(403).json({
        message: "This account is not a driver account"
      });
    }

    return res.status(200).json({
      message: "Login successful",
      token: jwt.sign(
        { id: user._id, role: user.role },
        "secretkey",
        { expiresIn: "7d" }
      ),
      userId: user._id,
      role: user.role,
      isAvailable: user.isAvailable || false
    });
  } catch (error) {
    console.log("LOGIN ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
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

module.exports = router;

