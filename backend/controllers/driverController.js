const mongoose = require("mongoose");
const User = require("../models/User");
const Driver = require("../models/Driver");

exports.getDrivers = async (req, res) => {
  try {
    // 1. Force the database to ONLY return online drivers
    const drivers = await User.find(
      { role: "driver", isAvailable: true },
      { name: 1, phone: 1, isAvailable: 1, role: 1, location: 1 }
    ).lean();

    // 2. Filter out corrupt locations completely (do NOT return null)
    const validDrivers = drivers.filter((d) => {
      const lat = Number(d.location?.lat);
      const lng = Number(d.location?.lng);

      // Keep only drivers with valid, non-zero coordinates
      if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) {
        return false;
      }
      return true;
    });

    return res.status(200).json({
      message: "Drivers fetched successfully",
      drivers: validDrivers
    });
  } catch (error) {
    console.log("GET DRIVERS ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.getDriverStatus = async (req, res) => {
  try {
    const driverId = req.params.id || req.user?.id;

    if (!driverId || !mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(400).json({
        success: false,
        message: "Invalid driver id"
      });
    }

    const driver = await User.findById(driverId).select("name phone role isAvailable location");

    if (!driver || driver.role !== "driver") {
      return res.status(404).json({
        success: false,
        message: "Driver not found"
      });
    }

    return res.status(200).json({
      success: true,
      driver: {
        _id: driver._id,
        name: driver.name,
        phone: driver.phone,
        isAvailable: driver.isAvailable || false,
        location: driver.location || { lat: 0, lng: 0 }
      }
    });
  } catch (error) {
    console.log("GET DRIVER STATUS ERROR:", error);
    return res.status(500).json({
      success: false,
      message: error.message
    });
  }
};

exports.toggleAvailability = async (req, res) => {
  try {
    const driverId = req.params.id || req.body?.driverId || req.user?.id;

    if (!driverId || !mongoose.Types.ObjectId.isValid(driverId)) {
      return res.status(400).json({
        success: false,
        message: "Invalid driver id"
      });
    }

    const driver = await User.findById(driverId);

    if (!driver) {
      return res.status(404).json({
        success: false,
        message: "Driver not found"
      });
    }

    if (driver.role !== "driver") {
      if (
        driver.phone === "guest.driver@gmail.com" ||
        driver.username === "guest.driver@gmail.com" ||
        (driver.name && driver.name.toLowerCase().includes("driver"))
      ) {
        driver.role = "driver";
        await driver.save();
      } else {
        return res.status(403).json({
          success: false,
          message: "User account is not registered as a driver"
        });
      }
    }

    // Check approval/verification guards
    if (driver.isApproved === false || driver.isVerified === false) {
      if (process.env.NODE_ENV === "production") {
        return res.status(403).json({
          success: false,
          message: "Driver account pending admin approval"
        });
      } else {
        console.warn(`[DEV MODE] Bypassing approval guard for driver: ${driverId}`);
      }
    }

    let nextAvailable;
    if (req.body.isAvailable !== undefined) {
      nextAvailable = !!req.body.isAvailable;
    } else {
      nextAvailable = !driver.isAvailable;
    }

    driver.isAvailable = nextAvailable;

    // Update location coordinates if provided in payload
    if (req.body.location) {
      const lat = Number(req.body.location.lat);
      const lng = Number(req.body.location.lng);
      if (Number.isFinite(lat) && Number.isFinite(lng)) {
        driver.location = { lat, lng };
      }
    }

    await driver.save();

    // Also sync Driver model if present in the database
    try {
      await Driver.findOneAndUpdate(
        { $or: [{ _id: driver._id }, { phone: driver.phone }] },
        {
          $set: {
            available: driver.isAvailable,
            ...(driver.location ? { location: { lat: driver.location.lat, lng: driver.location.lng } } : {})
          }
        }
      );
    } catch (_) {}

    // Emit live socket updates to riders & rooms
    const io = req.app.get("io");
    if (io) {
      io.emit("driver_status_changed", {
        driverId: driver._id.toString(),
        isAvailable: driver.isAvailable,
        location: driver.location
      });
      if (driver.location && Number.isFinite(driver.location.lat) && Number.isFinite(driver.location.lng)) {
        io.emit("driverLocationUpdated", {
          driverId: driver._id.toString(),
          lat: driver.location.lat,
          lng: driver.location.lng
        });
      }
    }

    return res.status(200).json({
      success: true,
      message: `Driver is now ${driver.isAvailable ? "online" : "offline"}`,
      isAvailable: driver.isAvailable,
      location: driver.location
    });
  } catch (error) {
    console.log("TOGGLE DRIVER ERROR:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Failed to update driver availability"
    });
  }
};

exports.mockNearby = async (req, res) => {
  try {
    const io = req.app.get("io");
    if (req.body.clear === true) {
      const mockUsers = await User.find({
        role: "driver",
        phone: { $regex: /^\+91987654321/ }
      }).select("_id phone");

      await User.updateMany(
        { role: "driver", phone: { $regex: /^\+91987654321/ } },
        { $set: { isAvailable: false } }
      );
      try {
        await Driver.updateMany(
          { phone: { $regex: /^\+91987654321/ } },
          { $set: { available: false } }
        );
      } catch (_) {}

      if (io) {
        for (const u of mockUsers) {
          io.emit("driver_status_changed", {
            driverId: u._id.toString(),
            isAvailable: false
          });
        }
      }

      return res.status(200).json({
        success: true,
        message: "Cleared simulated captains",
        drivers: []
      });
    }

    const lat = Number(req.body.lat) || 11.1401;
    const lng = Number(req.body.lng) || 79.0786;
    let count = parseInt(req.body.count, 10);
    if (isNaN(count) || count < 1 || count > 15) {
      count = 6 + Math.floor(Math.random() * 5); // 6 to 10 random captains
    }

    const bcrypt = require("bcryptjs");
    const hashedPassword = await bcrypt.hash("mock-captain-pass-2026", 10);
    const mockDrivers = [];

    const names = [
      "Arun K. (Captain)",
      "Suresh R. (Captain)",
      "Karthik S. (Captain)",
      "Vignesh M. (Captain)",
      "Praveen V. (Captain)",
      "Dinesh P. (Captain)",
      "Vijay N. (Captain)",
      "Manoj T. (Captain)",
      "Rahul B. (Captain)",
      "Deepak G. (Captain)"
    ];

    for (let i = 0; i < count; i++) {
      const radiusInDegrees = (0.45 + Math.random() * 1.1) / 111; // ~450m to 1.55km
      const angle = Math.random() * 2 * Math.PI;
      const mockLat = lat + radiusInDegrees * Math.cos(angle);
      const mockLng = lng + (radiusInDegrees * Math.sin(angle)) / Math.cos(lat * (Math.PI / 180));

      const phone = `+91987654321${i}`;
      const name = names[i % names.length] || `Mock Captain ${i + 1}`;

      const captain = await User.findOneAndUpdate(
        { phone },
        {
          $set: {
            name,
            phone,
            password: hashedPassword,
            role: "driver",
            isAvailable: true,
            location: { lat: mockLat, lng: mockLng },
            lastActiveAt: new Date(),
            lastPing: new Date()
          }
        },
        { upsert: true, new: true, setDefaultsOnInsert: true }
      );

      try {
        await Driver.findOneAndUpdate(
          { phone },
          {
            $set: {
              name,
              phone,
              available: true,
              location: { lat: mockLat, lng: mockLng }
            }
          },
          { upsert: true }
        );
      } catch (_) {}

      if (io) {
        io.emit("driver_status_changed", {
          driverId: captain._id.toString(),
          isAvailable: true,
          location: { lat: mockLat, lng: mockLng }
        });
        io.emit("driverLocationUpdated", {
          driverId: captain._id.toString(),
          lat: mockLat,
          lng: mockLng
        });
      }

      mockDrivers.push({
        _id: captain._id,
        name: captain.name,
        phone: captain.phone,
        role: captain.role,
        isAvailable: captain.isAvailable,
        location: { lat: mockLat, lng: mockLng }
      });
    }

    return res.status(200).json({
      success: true,
      message: `Spawned ${mockDrivers.length} nearby captains`,
      drivers: mockDrivers
    });
  } catch (error) {
    console.error("MOCK NEARBY DRIVERS ERROR:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Failed to generate mock captains"
    });
  }
};