const mongoose = require("mongoose");
const User = require("../models/User");

exports.getDrivers = async (req, res) => {
  try {
    const drivers = await User.find(
      { role: "driver" },
      { name: 1, phone: 1, isAvailable: 1, role: 1, location: 1 }
    ).lean();

    const sanitizedDrivers = drivers.map((d) => {
      const lat = Number(d.location?.lat);
      const lng = Number(d.location?.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) {
        return { ...d, location: null };
      }
      return d;
    });

    return res.status(200).json({
      message: "Drivers fetched successfully",
      drivers: sanitizedDrivers
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

    if (req.body.isAvailable !== undefined) {
      driver.isAvailable = !!req.body.isAvailable;
    } else {
      driver.isAvailable = !driver.isAvailable;
    }
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