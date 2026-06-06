const Ride = require("../models/Ride");
const User = require("../models/User");

const VALID_PAYMENT_METHODS = new Set(["Cash", "UPI", "Card"]);
const VALID_BOOKING_MODES = new Set(["normal", "negotiation"]);
const DEFAULT_NEGOTIATION_TIMEOUT_SECONDS = 45;

const getNegotiationTimeoutSeconds = () => {
  const configuredValue = Number(
    process.env.NEGOTIATION_TIMEOUT_SECONDS || DEFAULT_NEGOTIATION_TIMEOUT_SECONDS
  );

  if (!Number.isFinite(configuredValue)) {
    return DEFAULT_NEGOTIATION_TIMEOUT_SECONDS;
  }

  return Math.min(60, Math.max(30, Math.round(configuredValue)));
};

const normalizeText = (value) => {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim();
};

const parseCoordinate = (value) => {
  const parsedValue = Number(value);
  return Number.isFinite(parsedValue) ? parsedValue : null;
};

const parseFare = (value) => {
  const parsedValue = Number(value);
  return Number.isFinite(parsedValue) && parsedValue >= 0 ? parsedValue : null;
};

const isValidLatitude = (value) => value >= -90 && value <= 90;
const isValidLongitude = (value) => value >= -180 && value <= 180;

const calculateDistanceKm = (pickupLat, pickupLng, dropLat, dropLng) => {
  const toRadians = (value) => (value * Math.PI) / 180;
  const earthRadiusKm = 6371;
  const dLat = toRadians(dropLat - pickupLat);
  const dLng = toRadians(dropLng - pickupLng);
  const lat1 = toRadians(pickupLat);
  const lat2 = toRadians(dropLat);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
};

const calculateEstimatedFare = (pickupLat, pickupLng, dropLat, dropLng) => {
  const distanceKm = calculateDistanceKm(
    pickupLat,
    pickupLng,
    dropLat,
    dropLng
  );
  return Math.max(40, Math.round((40 + distanceKm * 12) * 100) / 100);
};

const sortOffers = (offers = []) =>
  [...offers].sort((firstOffer, secondOffer) => {
    if (firstOffer.offeredFare !== secondOffer.offeredFare) {
      return firstOffer.offeredFare - secondOffer.offeredFare;
    }

    return new Date(firstOffer.createdAt) - new Date(secondOffer.createdAt);
  });

const getPopulatedRide = (rideId) =>
  Ride.findById(rideId)
    .populate("userId", "name phone")
    .populate("driverId", "name phone location");

const emitRideEvent = async (io, eventName, rideId) => {
  const ride = await getPopulatedRide(rideId);
  if (ride) {
    io.emit(eventName, ride);
  }
};

const markOffersClosed = (ride, selectedOfferId = null) => {
  ride.offers = ride.offers.map((offer) => ({
    ...offer.toObject(),
    status:
      selectedOfferId && offer._id.toString() === selectedOfferId
        ? "selected"
        : "rejected"
  }));
};

const expireNegotiationIfNeeded = async (ride, io) => {
  if (
    !ride ||
    ride.status !== "negotiating" ||
    !ride.negotiationExpiresAt ||
    ride.negotiationExpiresAt > new Date()
  ) {
    return ride;
  }

  ride.status = "negotiation_expired";
  ride.negotiationStatus = "negotiation_expired";
  ride.negotiationExpiresAt = null;
  markOffersClosed(ride);
  await ride.save();
  const refreshedRide = await getPopulatedRide(ride._id);

  if (refreshedRide && io) {
    io.emit("negotiationExpired", refreshedRide);
    io.emit("negotiationClosed", refreshedRide);
  }

  return refreshedRide || ride;
};

const findNearestDriver = (drivers, pickupLatitude, pickupLongitude) =>
  drivers.reduce((nearestDriver, currentDriver) => {
    const currentLat = Number(currentDriver.location?.lat ?? 0);
    const currentLng = Number(currentDriver.location?.lng ?? 0);
    const currentDistance = Math.sqrt(
      Math.pow(currentLat - pickupLatitude, 2) +
        Math.pow(currentLng - pickupLongitude, 2)
    );

    if (!nearestDriver) {
      return { driver: currentDriver, distance: currentDistance };
    }

    return currentDistance < nearestDriver.distance
      ? { driver: currentDriver, distance: currentDistance }
      : nearestDriver;
  }, null)?.driver;

const ensureRideIsActionable = async (req, rideId) => {
  const io = req.app.get("io");
  let ride = await Ride.findById(rideId);

  if (!ride) {
    return { ride: null, io };
  }

  ride = await expireNegotiationIfNeeded(ride, io);
  return { ride, io };
};

exports.requestRide = async (req, res) => {
  try {
    const io = req.app.get("io");
    const {
      userId,
      pickup,
      destination,
      pickupAddress,
      pickupLat,
      pickupLng,
      pickupPlaceId,
      dropAddress,
      dropLat,
      dropLng,
      dropPlaceId,
      paymentMethod,
      bookingMode
    } = req.body;

    const resolvedPickupAddress = normalizeText(pickupAddress || pickup);
    const resolvedDropAddress = normalizeText(dropAddress || destination);
    const pickupLatitude = parseCoordinate(pickupLat);
    const pickupLongitude = parseCoordinate(pickupLng);
    const dropLatitude = parseCoordinate(dropLat);
    const dropLongitude = parseCoordinate(dropLng);
    const requestedPaymentMethod = normalizeText(paymentMethod) || "Cash";
    const requestedBookingMode = normalizeText(bookingMode) || "normal";

    if (
      !userId ||
      !resolvedPickupAddress ||
      !resolvedDropAddress ||
      pickupLatitude === null ||
      pickupLongitude === null ||
      dropLatitude === null ||
      dropLongitude === null
    ) {
      return res.status(400).json({
        message: "Pickup and drop addresses with coordinates are required"
      });
    }

    if (
      !isValidLatitude(pickupLatitude) ||
      !isValidLongitude(pickupLongitude) ||
      !isValidLatitude(dropLatitude) ||
      !isValidLongitude(dropLongitude)
    ) {
      return res.status(400).json({
        message:
          "Pickup and drop coordinates must be within valid latitude and longitude ranges"
      });
    }

    if (!VALID_PAYMENT_METHODS.has(requestedPaymentMethod)) {
      return res.status(400).json({
        message: "Payment method is invalid"
      });
    }

    if (!VALID_BOOKING_MODES.has(requestedBookingMode)) {
      return res.status(400).json({
        message: "Booking mode is invalid"
      });
    }

    const user = await User.findById(userId);

    if (!user) {
      return res.status(404).json({
        message: "User not found"
      });
    }

    const availableDrivers = await User.find({
      role: "driver",
      isAvailable: true
    });

    if (!availableDrivers.length) {
      return res.status(404).json({
        message: "No drivers available"
      });
    }

    const estimatedFare =
      parseFare(req.body.estimatedFare ?? req.body.fare) ??
      calculateEstimatedFare(
        pickupLatitude,
        pickupLongitude,
        dropLatitude,
        dropLongitude
      );

    const otp = Math.floor(1000 + Math.random() * 9000).toString();

    const ridePayload = {
      userId,
      pickup: resolvedPickupAddress,
      pickupAddress: resolvedPickupAddress,
      pickupLat: pickupLatitude,
      pickupLng: pickupLongitude,
      pickupPlaceId: pickupPlaceId || "",
      destination: resolvedDropAddress,
      dropAddress: resolvedDropAddress,
      dropLat: dropLatitude,
      dropLng: dropLongitude,
      dropPlaceId: dropPlaceId || "",
      paymentMethod: requestedPaymentMethod,
      paymentStatus: "Pending",
      bookingMode: requestedBookingMode,
      otp,
      estimatedFare,
      initialFare: estimatedFare,
      offeredFare: estimatedFare,
      finalFare: requestedBookingMode === "normal" ? estimatedFare : 0
    };

    if (requestedBookingMode === "negotiation") {
      const ride = new Ride({
        ...ridePayload,
        status: "negotiating",
        negotiationStatus: "open",
        negotiationExpiresAt: new Date(
          Date.now() + getNegotiationTimeoutSeconds() * 1000
        ),
        offers: []
      });

      await ride.save();
      io.emit("negotiationRideRequested", ride);

      return res.status(201).json({
        message: "Negotiation ride created successfully",
        ride
      });
    }

    const driver = findNearestDriver(
      availableDrivers,
      pickupLatitude,
      pickupLongitude
    );

    const ride = new Ride({
      ...ridePayload,
      driverId: driver?._id || null,
      status: "requested",
      negotiationStatus: "none"
    });

    await ride.save();

    if (driver) {
      driver.isAvailable = false;
      await driver.save();
    }

    io.emit("rideRequested", ride);

    return res.status(201).json({
      message: "Ride requested successfully. Waiting for driver confirmation.",
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
    const io = req.app.get("io");
    let ride = await Ride.findById(req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride = await expireNegotiationIfNeeded(ride, io);
    const hydratedRide = await getPopulatedRide(ride._id);

    return res.status(200).json({
      message: "Ride fetched successfully",
      ride: hydratedRide || ride
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
    const io = req.app.get("io");
    const { ride } = await ensureRideIsActionable(req, req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    if (ride.status !== "requested") {
      return res.status(400).json({
        message: "Ride cannot be accepted in its current state"
      });
    }

    ride.status = "accepted";
    await ride.save();

    io.emit("rideAccepted", ride);

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
    const io = req.app.get("io");
    const { ride } = await ensureRideIsActionable(req, req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    if (ride.status !== "accepted") {
      return res.status(400).json({
        message: "Only accepted rides can be started"
      });
    }

    const { otp } = req.body;
    if (!otp) {
      return res.status(400).json({
        message: "OTP is required to start the ride"
      });
    }

    if (ride.otp && ride.otp !== otp.toString().trim()) {
      return res.status(400).json({
        message: "Invalid OTP. Please enter the correct 4-digit code shown on the rider's screen."
      });
    }

    ride.status = "ongoing";
    await ride.save();

    io.emit("rideStarted", ride);

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
    const io = req.app.get("io");
    const { ride } = await ensureRideIsActionable(req, req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    if (ride.status !== "ongoing") {
      return res.status(400).json({
        message: "Only ongoing rides can be completed"
      });
    }

    ride.status = "completed";
    ride.finalFare =
      parseFare(ride.finalFare) ??
      parseFare(ride.offeredFare) ??
      parseFare(ride.estimatedFare) ??
      0;
    await ride.save();

    if (ride.driverId) {
      const driver = await User.findById(ride.driverId);
      if (driver) {
        driver.isAvailable = true;
        await driver.save();
      }
    }

    io.emit("rideCompleted", ride);

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
    const io = req.app.get("io");
    const { ride } = await ensureRideIsActionable(req, req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    if (ride.status === "completed" || ride.status === "cancelled") {
      return res.status(400).json({
        message: "Ride cannot be cancelled in its current state"
      });
    }

    ride.status = "cancelled";
    if (ride.bookingMode === "negotiation") {
      ride.negotiationStatus = "rejected";
      ride.negotiationExpiresAt = null;
      markOffersClosed(ride);
    }
    await ride.save();

    if (ride.driverId) {
      const driver = await User.findById(ride.driverId);
      if (driver) {
        driver.isAvailable = true;
        await driver.save();
      }
    }

    io.emit("rideCancelled", ride);
    if (ride.bookingMode === "negotiation") {
      io.emit("negotiationClosed", await getPopulatedRide(ride._id));
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

exports.payRide = async (req, res) => {
  try {
    const ride = await Ride.findById(req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride.paymentStatus = "Paid";
    await ride.save();

    return res.status(200).json({
      message: "Payment completed successfully",
      ride
    });
  } catch (error) {
    console.log("PAY RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.getRideOffers = async (req, res) => {
  try {
    const io = req.app.get("io");
    let ride = await Ride.findById(req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride = await expireNegotiationIfNeeded(ride, io);
    const hydratedRide = await getPopulatedRide(ride._id);

    return res.status(200).json({
      message: "Ride offers fetched successfully",
      offers: sortOffers(ride.offers.map((offer) => offer.toObject())),
      ride: hydratedRide || ride
    });
  } catch (error) {
    console.log("GET RIDE OFFERS ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.getDriverNegotiationRides = async (req, res) => {
  try {
    const io = req.app.get("io");
    const driverId = req.params.driverId;
    const rides = await Ride.find({
      status: "negotiating",
      negotiationStatus: { $in: ["open", "countered"] }
    })
      .populate("userId", "name phone")
      .sort({ createdAt: -1 });

    const activeRides = (
      await Promise.all(rides.map((ride) => expireNegotiationIfNeeded(ride, io)))
    ).filter((ride) => ride.status === "negotiating");

    const filteredRides = activeRides.filter((ride) => {
      const existingOffer = ride.offers.find(
        (offer) => offer.driverId.toString() === driverId
      );

      return !existingOffer || existingOffer.status === "pending" || existingOffer.status === "accepted_base";
    });

    return res.status(200).json({
      message: "Negotiation rides fetched successfully",
      rides: filteredRides
    });
  } catch (error) {
    console.log("GET DRIVER NEGOTIATION RIDES ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.getDriverRequests = async (req, res) => {
  try {
    const driverId = req.params.driverId;
    const rides = await Ride.find({
      status: "requested",
      driverId: driverId
    })
      .populate("userId", "name phone")
      .sort({ createdAt: -1 });

    return res.status(200).json({
      message: "Driver active requests fetched successfully",
      rides
    });
  } catch (error) {
    console.log("GET DRIVER REQUESTS ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.submitRideOffer = async (req, res) => {
  try {
    const { driverId, offeredFare, acceptBaseFare } = req.body;
    const { ride: actionableRide, io } = await ensureRideIsActionable(
      req,
      req.params.id
    );
    let ride = actionableRide;

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    if (ride.status !== "negotiating") {
      return res.status(400).json({
        message: "Ride is not accepting negotiation offers"
      });
    }

    const driver = await User.findById(driverId);

    if (!driver || driver.role !== "driver" || !driver.isAvailable) {
      return res.status(404).json({
        message: "Eligible driver not found"
      });
    }

    const nextFare = acceptBaseFare
      ? ride.estimatedFare
      : parseFare(offeredFare);

    if (nextFare === null) {
      return res.status(400).json({
        message: "Offer fare must be valid"
      });
    }

    const existingOffer = ride.offers.find(
      (offer) => offer.driverId.toString() === driverId
    );

    if (existingOffer) {
      existingOffer.offeredFare = nextFare;
      existingOffer.status = acceptBaseFare ? "accepted_base" : "pending";
      existingOffer.driverName = driver.name;
      existingOffer.driverPhone = driver.phone || "";
    } else {
      ride.offers.push({
        driverId,
        driverName: driver.name,
        driverPhone: driver.phone || "",
        offeredFare: nextFare,
        status: acceptBaseFare ? "accepted_base" : "pending"
      });
    }

    ride.negotiationStatus = "countered";
    ride.offeredFare = nextFare;
    ride.negotiationExpiresAt = new Date(
      Date.now() + getNegotiationTimeoutSeconds() * 1000
    );
    await ride.save();

    const submittedOffer = sortOffers(
      ride.offers.map((offer) => offer.toObject())
    ).find((offer) => offer.driverId.toString() === driverId);

    io.emit("negotiationOfferSubmitted", {
      rideId: ride._id,
      offer: submittedOffer
    });

    return res.status(200).json({
      message: acceptBaseFare
        ? "Base fare accepted successfully"
        : "Offer submitted successfully",
      ride,
      offer: submittedOffer
    });
  } catch (error) {
    console.log("SUBMIT RIDE OFFER ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.confirmRideOffer = async (req, res) => {
  try {
    const { ride: actionableRide, io } = await ensureRideIsActionable(
      req,
      req.params.id
    );
    let ride = actionableRide;
    const { offerId } = req.body;

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    if (ride.status !== "negotiating") {
      return res.status(400).json({
        message: "Ride negotiation is no longer active"
      });
    }

    const selectedOffer = ride.offers.id(offerId);

    if (!selectedOffer) {
      return res.status(404).json({
        message: "Offer not found"
      });
    }

    markOffersClosed(ride, offerId);
    ride.driverId = selectedOffer.driverId;
    ride.status = "accepted";
    ride.negotiationStatus = "accepted";
    ride.finalFare = selectedOffer.offeredFare;
    ride.offeredFare = selectedOffer.offeredFare;
    ride.negotiationExpiresAt = null;
    await ride.save();

    const driver = await User.findById(selectedOffer.driverId);
    if (driver) {
      driver.isAvailable = false;
      await driver.save();
    }

    const refreshedRide = await Ride.findById(ride._id)
      .populate("userId", "name phone")
      .populate("driverId", "name phone location");

    io.emit("negotiationOfferAcceptedByUser", refreshedRide);
    io.emit("negotiationClosed", refreshedRide);
    io.emit("rideAccepted", refreshedRide);

    return res.status(200).json({
      message: "Offer selected successfully",
      ride: refreshedRide
    });
  } catch (error) {
    console.log("CONFIRM RIDE OFFER ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.negotiateFare = async (req, res) => exports.submitRideOffer(req, res);

exports.acceptFare = async (req, res) => exports.confirmRideOffer(req, res);

exports.rejectFare = async (req, res) => {
  try {
    const { ride } = await ensureRideIsActionable(req, req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    ride.negotiationStatus = "rejected";
    await ride.save();

    return res.status(200).json({
      message: "Offer rejected successfully",
      ride
    });
  } catch (error) {
    console.log("REJECT FARE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.getDashboardStats = async (req, res) => {
  try {
    const [
      totalRides,
      completedRides,
      cancelledRides,
      ongoingRides,
      availableDrivers
    ] = await Promise.all([
      Ride.countDocuments(),
      Ride.countDocuments({ status: "completed" }),
      Ride.countDocuments({ status: "cancelled" }),
      Ride.countDocuments({ status: "ongoing" }),
      User.countDocuments({ role: "driver", isAvailable: true })
    ]);

    return res.status(200).json({
      message: "Dashboard stats fetched successfully",
      totalRides,
      completedRides,
      cancelledRides,
      ongoingRides,
      availableDrivers
    });
  } catch (error) {
    console.log("GET DASHBOARD STATS ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};

exports.expireOpenNegotiations = async (io) => {
  const rides = await Ride.find({
    status: "negotiating",
    negotiationStatus: { $in: ["open", "countered"] },
    negotiationExpiresAt: { $lte: new Date() }
  });

  await Promise.all(rides.map((ride) => expireNegotiationIfNeeded(ride, io)));
};
