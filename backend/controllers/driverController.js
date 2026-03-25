const mongoose = require("mongoose");
const User = require("../models/User");

exports.getDrivers = async (req, res) => {
  try {
    const drivers = await User.find(
      { role: "driver" },
      { name: 1, phone: 1, isAvailable: 1, role: 1 }
    ).lean();

    return res.status(200).json({
      message: "Drivers fetched successfully",
      drivers
    });
  } catch (error) {
    console.log("GET DRIVERS ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.toggleAvailability = async (req, res) => {
  try {
    const driverId = req.params.id;

    if (!mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(400).json({
        message: "Invalid driver id"
      });
    }

    const driver = await User.findById(driverId);

    if (!driver || driver.role !== "driver") {
      return res.status(404).json({
        message: "Driver not found"
      });
    }

    driver.isAvailable = !driver.isAvailable;
    await driver.save();

    return res.status(200).json({
      message: "Driver availability updated",
      isAvailable: driver.isAvailable
    });
  } catch (error) {
    console.log("TOGGLE DRIVER ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};