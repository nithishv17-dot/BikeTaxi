const Ride = require("../models/Ride");
const User = require("../models/User");

exports.requestRide = async (req, res) => {
  try {
    const { userId, pickup, destination } = req.body;

    if (!userId || !pickup || !destination) {
      return res.status(400).json({
        message: "All fields are required"
      });
    }

    const drivers = await User.find({
      role: "driver",
      isAvailable: true
    });

    if (!drivers.length) {
      return res.status(404).json({
        message: "No drivers available"
      });
    }

    const driver = drivers[Math.floor(Math.random() * drivers.length)];

    const ride = new Ride({
      userId,
      driverId: driver._id,
      pickup,
      destination,
      status: "accepted"
    });

    await ride.save();

    driver.isAvailable = false;
    await driver.save();

    return res.status(201).json({
      message: "Ride requested successfully",
      ride
    });
  } catch (error) {
    console.log("REQUEST RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.getRide = async (req, res) => {
  try {
    const ride = await Ride.findById(req.params.id)
      .populate("userId", "name phone")
      .populate("driverId", "name phone");

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    return res.status(200).json({
      message: "Ride fetched successfully",
      ride
    });
  } catch (error) {
    console.log("GET RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.acceptRide = async (req, res) => {
  try {
    const ride = await Ride.findById(req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride.status = "accepted";
    await ride.save();

    return res.status(200).json({
      message: "Ride accepted successfully",
      ride
    });
  } catch (error) {
    console.log("ACCEPT RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.startRide = async (req, res) => {
  try {
    const ride = await Ride.findById(req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride.status = "ongoing";
    await ride.save();

    return res.status(200).json({
      message: "Ride started successfully",
      ride
    });
  } catch (error) {
    console.log("START RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.completeRide = async (req, res) => {
  try {
    const ride = await Ride.findById(req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride.status = "completed";
    await ride.save();

    if (ride.driverId) {
      const driver = await User.findById(ride.driverId);
      if (driver) {
        driver.isAvailable = true;
        await driver.save();
      }
    }

    return res.status(200).json({
      message: "Ride completed successfully",
      ride
    });
  } catch (error) {
    console.log("COMPLETE RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.cancelRide = async (req, res) => {
  try {
    const ride = await Ride.findById(req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride.status = "cancelled";
    await ride.save();

    if (ride.driverId) {
      const driver = await User.findById(ride.driverId);
      if (driver) {
        driver.isAvailable = true;
        await driver.save();
      }
    }

    return res.status(200).json({
      message: "Ride cancelled successfully",
      ride
    });
  } catch (error) {
    console.log("CANCEL RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.getUserRides = async (req, res) => {
  try {
    const rides = await Ride.find({ userId: req.params.userId })
      .populate("driverId", "name phone")
      .sort({ createdAt: -1 });

    return res.status(200).json({
      message: "User rides fetched successfully", 
      rides
    });
  } catch (error) {
    console.log("GET USER RIDES ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};