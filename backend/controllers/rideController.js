const mongoose = require("mongoose");
const Ride = require("../models/Ride");
const User = require("../models/User");
const Driver = require("../models/Driver");
const { calculateFare } = require("../services/fareService");

const extractObjectId = (input) => {
  if (!input) return null;
  
  if (typeof input === "string" && mongoose.Types.ObjectId.isValid(input)) {
    return input;
  }
  
  if (input instanceof mongoose.Types.ObjectId) {
    return input.toString();
  }

  if (typeof input === "object") {
    const idVal = input._id || input.id;
    if (idVal && mongoose.Types.ObjectId.isValid(idVal.toString())) {
      return idVal.toString();
    }
  }

  if (typeof input === "string") {
    let cleaned = input.trim();
    if (cleaned.startsWith("{") && cleaned.endsWith("}")) {
      try {
        const parsed = JSON.parse(cleaned);
        const idVal = parsed._id || parsed.id;
        if (idVal && mongoose.Types.ObjectId.isValid(idVal.toString())) {
          return idVal.toString();
        }
      } catch (e) {
        const match = cleaned.match(/_id\s*:\s*["']?([a-fA-F0-9]{24})["']?/);
        if (match && match[1]) {
          return match[1];
        }
        const hexMatch = cleaned.match(/([a-fA-F0-9]{24})/);
        if (hexMatch && hexMatch[1]) {
          return hexMatch[1];
        }
      }
    }
    const directHexMatch = cleaned.match(/([a-fA-F0-9]{24})/);
    if (directHexMatch && directHexMatch[1]) {
      return directHexMatch[1];
    }
  }

  return null;
};

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

const calculateEstimatedFare = async (pickupLat, pickupLng, dropLat, dropLng) => {
  const distanceKm = calculateDistanceKm(
    pickupLat,
    pickupLng,
    dropLat,
    dropLng
  );

  const fare = await calculateFare({
    distanceKm,
    durationMinutes: 0,
    surgeMultiplier: 1,
    walletAmount: 0,
  });

  return fare.totalFare;
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

const findNearestDriver = (drivers, pickupLatitude, pickupLongitude) => {
  const validDrivers = drivers.filter((d) => {
    const lat = Number(d.location?.lat);
    const lng = Number(d.location?.lng);
    return Number.isFinite(lat) && Number.isFinite(lng) && lat !== 0 && lng !== 0;
  });

  if (!validDrivers.length) return null;

  return validDrivers.reduce((nearestDriver, currentDriver) => {
    const currentLat = Number(currentDriver.location.lat);
    const currentLng = Number(currentDriver.location.lng);
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
};

const ensureRideIsActionable = async (req, rideId) => {
  const io = req.app.get("io");
  let ride = await Ride.findById(rideId);

  if (!ride) {
    return { ride: null, io };
  }

  ride = await expireNegotiationIfNeeded(ride, io);
  return { ride, io };
};

const getOrCreateDemoCaptain = async (pickupLat, pickupLng, excludeIds = []) => {
  let demoCaptain = await User.findOne({
    role: "driver",
    isAvailable: true,
    _id: { $nin: excludeIds },
    phone: { $regex: /^\+91987654321/ }
  });

  if (!demoCaptain) {
    demoCaptain = await User.findOne({
      role: "driver",
      isAvailable: true,
      _id: { $nin: excludeIds }
    });
  }

  const fallbackLat = Number(pickupLat) + 0.0055;
  const fallbackLng = Number(pickupLng) + 0.0045;

  if (!demoCaptain) {
    const bcrypt = require("bcryptjs");
    const hashedPassword = await bcrypt.hash("mock-captain-pass-2026", 10);
    demoCaptain = await User.findOneAndUpdate(
      { phone: "+919876543211" },
      {
        $set: {
          name: "Arun K. (Captain)",
          phone: "+919876543211",
          password: hashedPassword,
          role: "driver",
          isAvailable: true,
          location: { lat: fallbackLat, lng: fallbackLng },
          lastActiveAt: new Date(),
          lastPing: new Date()
        }
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
  } else if (
    !demoCaptain.location ||
    !Number.isFinite(Number(demoCaptain.location.lat)) ||
    Number(demoCaptain.location.lat) === 0
  ) {
    demoCaptain.location = { lat: fallbackLat, lng: fallbackLng };
    await demoCaptain.save();
  }

  return demoCaptain;
};

const scheduleDemoCounterOffers = (rideId, io) => {
  const demoCaptainTemplates = [
    { name: "Arun K. (Captain)", phone: "+919876543210" },
    { name: "Suresh R. (Captain)", phone: "+919876543211" },
    { name: "Karthik S. (Captain)", phone: "+919876543212" },
    { name: "Vignesh M. (Captain)", phone: "+919876543213" },
    { name: "Praveen V. (Captain)", phone: "+919876543214" },
    { name: "Dinesh P. (Captain)", phone: "+919876543215" }
  ];

  const offerCount = 4 + Math.floor(Math.random() * 3); // 4 to 6 offers

  for (let i = 0; i < offerCount; i++) {
    setTimeout(async () => {
      try {
        const latestRide = await Ride.findById(rideId);
        if (!latestRide || latestRide.status !== "negotiating") {
          return;
        }

        const tpl = demoCaptainTemplates[i % demoCaptainTemplates.length];
        const radiusDeg = (0.4 + Math.random() * 1.0) / 111;
        const angle = Math.random() * 2 * Math.PI;
        const offsetLat = latestRide.pickupLat + radiusDeg * Math.cos(angle);
        const offsetLng =
          latestRide.pickupLng +
          (radiusDeg * Math.sin(angle)) /
            Math.max(0.2, Math.abs(Math.cos(latestRide.pickupLat * (Math.PI / 180))));

        let demoCaptain = await User.findOne({ phone: tpl.phone, role: "driver" });
        if (!demoCaptain) {
          const bcrypt = require("bcryptjs");
          const hashedPassword = await bcrypt.hash("mock-captain-pass-2026", 10);
          demoCaptain = await User.findOneAndUpdate(
            { phone: tpl.phone },
            {
              $set: {
                name: tpl.name,
                phone: tpl.phone,
                password: hashedPassword,
                role: "driver",
                isAvailable: true,
                location: { lat: offsetLat, lng: offsetLng },
                lastActiveAt: new Date(),
                lastPing: new Date()
              }
            },
            { upsert: true, new: true, setDefaultsOnInsert: true }
          );
        } else if (
          !demoCaptain.location ||
          !Number.isFinite(Number(demoCaptain.location.lat)) ||
          Number(demoCaptain.location.lat) === 0
        ) {
          demoCaptain.location = { lat: offsetLat, lng: offsetLng };
          await demoCaptain.save();
        }

        const baseOffer = Number(
          latestRide.offeredFare || latestRide.estimatedFare || 35
        );
        const multiplier = 1.0 + Math.random() * 0.25; // offeredFare to offeredFare * 1.25
        const counterFare = Math.max(
          Math.round(baseOffer * multiplier),
          Math.round(baseOffer)
        );
        const driverRating = Number((4.6 + Math.random() * 0.3).toFixed(1)); // 4.6 - 4.9
        const etaMins = 2 + Math.floor(Math.random() * 5); // 2 - 6 min
        const eta = `${etaMins} min`;

        const existingIdx = latestRide.offers.findIndex(
          (offer) => offer.driverId.toString() === demoCaptain._id.toString()
        );
        if (existingIdx !== -1) {
          latestRide.offers[existingIdx].offeredFare = counterFare;
          latestRide.offers[existingIdx].driverRating = driverRating;
          latestRide.offers[existingIdx].eta = eta;
          latestRide.offers[existingIdx].status = "pending";
          latestRide.offers[existingIdx].driverName =
            demoCaptain.name || tpl.name;
        } else {
          latestRide.offers.push({
            driverId: demoCaptain._id,
            driverName: demoCaptain.name || tpl.name,
            driverPhone: demoCaptain.phone || tpl.phone,
            offeredFare: counterFare,
            driverRating,
            eta,
            status: "pending"
          });
        }

        latestRide.negotiationStatus = "countered";
        latestRide.counterOffer = counterFare;
        if (!latestRide.driverId) {
          latestRide.driverId = demoCaptain._id;
        }
        await latestRide.save();

        const populatedRide = await getPopulatedRide(latestRide._id);
        const createdOffer =
          latestRide.offers[latestRide.offers.length - 1];

        if (io) {
          const payload = {
            rideId: latestRide._id.toString(),
            ride: populatedRide,
            offer: createdOffer,
            counterOffer: counterFare,
            negotiationStatus: "countered",
            captain: {
              _id: demoCaptain._id.toString(),
              name: demoCaptain.name || tpl.name,
              phone: demoCaptain.phone || tpl.phone,
              location: demoCaptain.location
            }
          };
          io.to(`ride_${latestRide._id}`).emit("ride_counter_offer", payload);
          io.to(`user_${latestRide.userId}`).emit("ride_counter_offer", payload);
          io.to(`ride_${latestRide._id}`).emit("ride_updated", populatedRide);
          io.to(`user_${latestRide.userId}`).emit("ride_updated", populatedRide);
          io.emit("negotiationOfferSubmitted", {
            rideId: latestRide._id,
            offer: createdOffer
          });
        }
      } catch (err) {
        console.error("[DEMO COUNTER OFFER ERROR]:", err.message);
      }
    }, (i + 1) * 1200);
  }
};

const scheduleDemoNormalAccept = (rideId, io) => {
  setTimeout(async () => {
    try {
      const latestRide = await Ride.findById(rideId);
      if (!latestRide || latestRide.status !== "requested") {
        return;
      }

      let driver = latestRide.driverId
        ? await User.findById(latestRide.driverId)
        : null;
      if (!driver) {
        driver = await getOrCreateDemoCaptain(
          latestRide.pickupLat,
          latestRide.pickupLng
        );
      }

      latestRide.driverId = driver._id;
      latestRide.status = "accepted";
      latestRide.otp = Math.floor(1000 + Math.random() * 9000).toString();
      await latestRide.save();

      const refreshedRide = await getPopulatedRide(latestRide._id);
      if (io && refreshedRide) {
        io.to(`ride_${latestRide._id}`).emit("ride_updated", refreshedRide);
        io.to(`user_${latestRide.userId}`).emit("ride_updated", refreshedRide);
        io.emit("rideAccepted", refreshedRide);
      }
    } catch (err) {
      console.error("[DEMO NORMAL ACCEPT ERROR]:", err.message);
    }
  }, 2500);
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

    const extractedUserId = extractObjectId(userId);
    if (!extractedUserId || !mongoose.Types.ObjectId.isValid(extractedUserId)) {
      return res.status(400).json({
        message: "Invalid or malformed user id"
      });
    }

    const resolvedPickupAddress = normalizeText(pickupAddress || pickup);
    const resolvedDropAddress = normalizeText(dropAddress || destination);
    const pickupLatitude = parseCoordinate(pickupLat);
    const pickupLongitude = parseCoordinate(pickupLng);
    const dropLatitude = parseCoordinate(dropLat);
    const dropLongitude = parseCoordinate(dropLng);
    const requestedPaymentMethod = normalizeText(paymentMethod) || "Cash";
    const requestedBookingMode = normalizeText(bookingMode) || "normal";

    if (
      !extractedUserId ||
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

    const user = await User.findById(extractedUserId);

    if (!user) {
      return res.status(404).json({
        message: "User not found"
      });
    }

    // Cancel any previous active rides for this user to avoid conflicts
    const activeRides = await Ride.find({
      userId: extractedUserId,
      status: { $in: ["requested", "negotiating", "accepted", "ongoing"] }
    });

    for (const oldRide of activeRides) {
      oldRide.status = "cancelled";
      if (oldRide.bookingMode === "negotiation") {
        oldRide.negotiationStatus = "rejected";
        oldRide.negotiationExpiresAt = null;
      }
      await oldRide.save();

      // Release driver if assigned
      if (oldRide.driverId) {
        const oldDriver = await User.findById(oldRide.driverId);
        if (oldDriver) {
          oldDriver.isAvailable = true;
          await oldDriver.save();
        }
      }
      
      // Emit event
      const refreshedOldRide = await getPopulatedRide(oldRide._id);
      if (refreshedOldRide && io) {
        io.emit("rideCancelled", refreshedOldRide);
      }
    }

    const busyRides = await Ride.find({
      status: { $in: ["requested", "accepted", "started", "negotiating"] },
      driverId: { $ne: null }
    });
    const busyDriverIds = busyRides.map(r => r.driverId.toString());
    console.log("DEBUG MATCHING:", {
      busyDriverIds,
      allDriversCount: await User.countDocuments({ role: "driver" }),
      onlineDrivers: await User.find({ role: "driver", isAvailable: true }).lean()
    });

    const rawDemoMode = req.body.isDemoMode;
    const isDemoMode = rawDemoMode === true;

    let availableDrivers = await User.find({
      role: "driver",
      isAvailable: true,
      _id: { $nin: busyDriverIds }
    });

    if (!availableDrivers.length) {
      if (isDemoMode) {
        const virtualCaptain = await getOrCreateDemoCaptain(
          pickupLatitude,
          pickupLongitude,
          busyDriverIds
        );
        availableDrivers = [virtualCaptain];
      } else {
        return res.status(404).json({
          message: "No drivers available"
        });
      }
    }

    const estimatedFare =
      parseFare(req.body.estimatedFare ?? req.body.fare) ??
      (await calculateEstimatedFare(
        pickupLatitude,
        pickupLongitude,
        dropLatitude,
        dropLongitude
      ));
    const offeredFare =
      parseFare(req.body.offeredFare ?? req.body.estimatedFare ?? req.body.fare) ??
      estimatedFare;

    const ridePayload = {
      userId: extractedUserId,
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
      isDemoMode: Boolean(isDemoMode),
      otp: "",
      estimatedFare,
      initialFare: estimatedFare,
      offeredFare,
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

      if (isDemoMode) {
        scheduleDemoCounterOffers(ride._id, io);
      }

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
      negotiationStatus: "none",
      negotiationExpiresAt: new Date(
        Date.now() + getNegotiationTimeoutSeconds() * 1000
      )
    });

    await ride.save();

    if (driver) {
      // Cancel any other active/pending requested normal rides assigned to this driver
      const duplicateRequests = await Ride.find({
        _id: { $ne: ride._id },
        driverId: driver._id,
        status: "requested",
        bookingMode: "normal"
      });
      for (const oldReq of duplicateRequests) {
        oldReq.status = "cancelled";
        await oldReq.save();
        if (io) {
          const refreshedOld = await getPopulatedRide(oldReq._id);
          if (refreshedOld) {
            io.emit("rideCancelled", refreshedOld);
          }
        }
      }
    }

    io.emit("rideRequested", ride);

    if (rawDemoMode === true) {
      scheduleDemoNormalAccept(ride._id, io);
    }

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

    const assignedDriverId = req.body?.driverId || req.user?.id || ride.driverId;
    if (assignedDriverId) {
      ride.driverId = assignedDriverId;
    }

    ride.status = "accepted";
    ride.otp = Math.floor(1000 + Math.random() * 9000).toString();
    await ride.save();

    if (assignedDriverId) {
      await User.findByIdAndUpdate(assignedDriverId, { $set: { isAvailable: false } });
      try {
        await Driver.findOneAndUpdate(
          { $or: [{ _id: assignedDriverId }, { phone: (await User.findById(assignedDriverId))?.phone }] },
          { $set: { available: false } }
        );
      } catch (_) {}

      io.to(`driver_${assignedDriverId}`).emit("driver_availability_changed", {
        driverId: assignedDriverId.toString(),
        isAvailable: false
      });
      io.emit("driver_status_changed", {
        driverId: assignedDriverId.toString(),
        isAvailable: false
      });
    }

    const refreshedRide = await getPopulatedRide(ride._id);
    io.emit("rideAccepted", refreshedRide);

    return res.status(200).json({
      message: "Ride accepted successfully",
      ride: refreshedRide || ride
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

    const refreshedRide = await getPopulatedRide(ride._id);
    io.emit("rideStarted", refreshedRide);

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

    const fareBreakdown = await calculateFare({
      distanceKm: req.body.distanceKm ?? 0,
      durationMinutes: req.body.durationMinutes ?? 0,
      surgeMultiplier: req.body.surgeMultiplier ?? 1,
      couponCode: req.body.couponCode,
      walletAmount: req.body.walletAmount ?? 0,
      rideId: ride._id,
      firstRideOnly: Boolean(req.body.firstRideOnly),
    });

    ride.status = "completed";
    ride.finalFare = fareBreakdown.totalFare;
    ride.estimatedFare = fareBreakdown.totalFare;
    ride.initialFare = fareBreakdown.totalFare;
    ride.offeredFare = fareBreakdown.totalFare;
    await ride.save();

    if (ride.driverId) {
      const driver = await User.findById(ride.driverId);
      if (driver) {
        driver.isAvailable = true;
        await driver.save();
      }
      try {
        await Driver.findOneAndUpdate(
          { $or: [{ _id: ride.driverId }, { phone: driver?.phone }] },
          { $set: { available: true } }
        );
      } catch (_) {}

      io.to(`driver_${ride.driverId}`).emit("driver_availability_changed", {
        driverId: ride.driverId.toString(),
        isAvailable: true
      });
      io.emit("driver_status_changed", {
        driverId: ride.driverId.toString(),
        isAvailable: true
      });
    }

    const refreshedRide = await getPopulatedRide(ride._id);
    io.emit("rideCompleted", refreshedRide);

    return res.status(200).json({
      message: "Ride completed successfully",
      ride,
      fare: fareBreakdown
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
      try {
        await Driver.findOneAndUpdate(
          { $or: [{ _id: ride.driverId }, { phone: driver?.phone }] },
          { $set: { available: true } }
        );
      } catch (_) {}

      io.to(`driver_${ride.driverId}`).emit("driver_availability_changed", {
        driverId: ride.driverId.toString(),
        isAvailable: true
      });
      io.emit("driver_status_changed", {
        driverId: ride.driverId.toString(),
        isAvailable: true
      });
    }

    const refreshedRide = await getPopulatedRide(ride._id);
    io.emit("rideCancelled", refreshedRide);
    if (ride.bookingMode === "negotiation") {
      io.emit("negotiationClosed", refreshedRide);
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
    const extractedUserId = extractObjectId(req.params.userId);
    if (!extractedUserId || !mongoose.Types.ObjectId.isValid(extractedUserId)) {
      return res.status(400).json({
        message: "Invalid or malformed user id"
      });
    }
    const rides = await Ride.find({ userId: extractedUserId })
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

    if (ride.status === "cancelled") {
      return res.status(400).json({
        message: "Cancelled rides cannot be paid"
      });
    }

    ride.paymentStatus = "Paid";
    await ride.save();

    const io = req.app.get("io");
    if (io) {
      const refreshedRide = await getPopulatedRide(ride._id);
      io.emit("rideCompleted", refreshedRide);
    }

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
    const extractedDriverId = extractObjectId(req.params.driverId);
    if (!extractedDriverId || !mongoose.Types.ObjectId.isValid(extractedDriverId)) {
      return res.status(400).json({
        message: "Invalid or malformed driver id"
      });
    }
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
        (offer) => offer.driverId.toString() === extractedDriverId
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
    const extractedDriverId = extractObjectId(req.params.driverId);
    if (!extractedDriverId || !mongoose.Types.ObjectId.isValid(extractedDriverId)) {
      return res.status(400).json({
        message: "Invalid or malformed driver id"
      });
    }
    const rides = await Ride.find({
      status: "requested",
      driverId: extractedDriverId
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
    const extractedDriverId = extractObjectId(driverId);
    if (!extractedDriverId || !mongoose.Types.ObjectId.isValid(extractedDriverId)) {
      return res.status(400).json({
        message: "Invalid or malformed driver id"
      });
    }
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

    const driver = await User.findById(extractedDriverId);

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
      (offer) => offer.driverId.toString() === extractedDriverId
    );

    if (existingOffer) {
      existingOffer.offeredFare = nextFare;
      existingOffer.status = acceptBaseFare ? "accepted_base" : "pending";
      existingOffer.driverName = driver.name;
      existingOffer.driverPhone = driver.phone || "";
    } else {
      ride.offers.push({
        driverId: extractedDriverId,
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
    const { offerId } = req.body || {};

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

    let selectedOffer = null;
    let extractedOfferId = offerId ? extractObjectId(offerId) : null;

    if (extractedOfferId) {
      if (!mongoose.Types.ObjectId.isValid(extractedOfferId)) {
        return res.status(400).json({
          message: "Invalid or malformed offer id"
        });
      }
      selectedOffer = ride.offers.id(extractedOfferId);
    } else if (ride.offers && ride.offers.length > 0) {
      selectedOffer =
        [...ride.offers].reverse().find((o) => o.status === "pending") ||
        ride.offers[ride.offers.length - 1];
      extractedOfferId = selectedOffer?._id?.toString();
    }

    let acceptedDriverId = selectedOffer?.driverId || ride.driverId;
    let acceptedFare =
      selectedOffer?.offeredFare || ride.counterOffer || ride.offeredFare;

    if (!selectedOffer && !(ride.counterOffer > 0 && acceptedDriverId)) {
      return res.status(404).json({
        message: "Offer not found"
      });
    }

    if (extractedOfferId) {
      markOffersClosed(ride, extractedOfferId);
    }
    ride.driverId = acceptedDriverId;
    ride.status = "accepted";
    ride.negotiationStatus = "accepted";
    ride.finalFare = acceptedFare;
    ride.offeredFare = acceptedFare;
    ride.negotiationExpiresAt = null;
    ride.otp = Math.floor(1000 + Math.random() * 9000).toString();
    await ride.save();

    const driver = acceptedDriverId
      ? await User.findById(acceptedDriverId)
      : null;
    if (driver) {
      driver.isAvailable = false;
      await driver.save();
    }
    if (acceptedDriverId) {
      try {
        await Driver.findOneAndUpdate(
          { $or: [{ _id: acceptedDriverId }, { phone: driver?.phone }] },
          { $set: { available: false } }
        );
      } catch (_) {}

      io.to(`driver_${acceptedDriverId}`).emit("driver_availability_changed", {
        driverId: acceptedDriverId.toString(),
        isAvailable: false
      });
      io.emit("driver_status_changed", {
        driverId: acceptedDriverId.toString(),
        isAvailable: false
      });
    }

    const refreshedRide = await Ride.findById(ride._id)
      .populate("userId", "name phone")
      .populate("driverId", "name phone location");

    io.to(`ride_${ride._id}`).emit("ride_updated", refreshedRide);
    io.to(`user_${ride.userId}`).emit("ride_updated", refreshedRide);
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
    const { ride, io } = await ensureRideIsActionable(req, req.params.id);

    if (!ride) {
      return res.status(404).json({
        message: "Ride not found"
      });
    }

    markOffersClosed(ride);
    ride.negotiationStatus = "rejected";
    ride.counterOffer = 0;
    if (ride.status === "negotiating") {
      ride.driverId = null;
    }
    await ride.save();

    const refreshedRide = await getPopulatedRide(ride._id);
    if (io && refreshedRide) {
      io.to(`ride_${ride._id}`).emit("ride_updated", refreshedRide);
      io.to(`user_${ride.userId}`).emit("ride_updated", refreshedRide);
    }

    return res.status(200).json({
      message: "Offer rejected successfully",
      ride: refreshedRide || ride
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

exports.expireRequestedRides = async (io) => {
  const expiredRides = await Ride.find({
    bookingMode: "normal",
    status: "requested",
    negotiationExpiresAt: { $lte: new Date() }
  });

  for (const ride of expiredRides) {
    ride.status = "cancelled";
    await ride.save();

    if (ride.driverId) {
      const driver = await User.findById(ride.driverId);
      if (driver) {
        driver.isAvailable = true;
        await driver.save();
      }
      try {
        await Driver.findOneAndUpdate(
          { $or: [{ _id: ride.driverId }, { phone: driver?.phone }] },
          { $set: { available: true } }
        );
      } catch (_) {}

      io.to(`driver_${ride.driverId}`).emit("driver_availability_changed", {
        driverId: ride.driverId.toString(),
        isAvailable: true
      });
      io.emit("driver_status_changed", {
        driverId: ride.driverId.toString(),
        isAvailable: true
      });
    }

    const refreshedRide = await getPopulatedRide(ride._id);
    if (refreshedRide && io) {
      io.emit("rideCancelled", refreshedRide);
    }
  }
};

exports.getActiveRide = async (req, res) => {
  try {
    const userId = req.user.id;
    // Find the latest active ride for the user (either rider or driver)
    const ride = await Ride.findOne({
      $or: [
        { userId: userId },
        { driverId: userId }
      ],
      status: { $in: ["requested", "accepted", "ongoing", "negotiating"] }
    }).sort({ createdAt: -1 });

    if (!ride) {
      // Also check if there is a completed ride where payment is still pending
      const pendingPaymentRide = await Ride.findOne({
        $or: [
          { userId: userId },
          { driverId: userId }
        ],
        status: "completed",
        paymentStatus: "Pending"
      }).sort({ createdAt: -1 });

      if (pendingPaymentRide) {
        const hydratedPending = await getPopulatedRide(pendingPaymentRide._id);
        return res.status(200).json({
          message: "Active ride found (Pending Payment)",
          ride: hydratedPending || pendingPaymentRide
        });
      }

      return res.status(200).json({
        message: "No active ride",
        ride: null
      });
    }

    const hydratedRide = await getPopulatedRide(ride._id);
    return res.status(200).json({
      message: "Active ride found",
      ride: hydratedRide || ride
    });
  } catch (error) {
    console.log("GET ACTIVE RIDE ERROR:", error);
    return res.status(500).json({
      message: error.message
    });
  }
};
