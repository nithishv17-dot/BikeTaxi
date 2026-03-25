const express = require("express");
const router = express.Router();
const User = require("../models/User");

router.post("/register", async (req, res) => {
  try {
    console.log("REGISTER BODY:", req.body);

    const { name, phone, password } = req.body;

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

    const user = new User({ name, phone, password });
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
    const { phone, password } = req.body;

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

    return res.status(200).json({
      message: "Login successful",
      userId: user._id
    });
  } catch (error) {
    console.log("LOGIN ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
});
const driverController = require("../controllers/driverController");

router.post("/drivers-list", driverController.getDrivers);
module.exports = router;