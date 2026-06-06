const express = require("express");
const router = express.Router();
const rideController = require("../controllers/rideController");
const authMiddleware = require("../middleware/authMiddleware");

router.use(authMiddleware);
router.get("/dashboard", rideController.getDashboardStats);
router.post("/request", rideController.requestRide);
router.get("/driver/:driverId/negotiations", rideController.getDriverNegotiationRides);
router.get("/driver/:driverId/requests", rideController.getDriverRequests);
router.get("/user/:userId/history", rideController.getUserRides);
router.post("/accept/:id", rideController.acceptRide);
router.post("/start/:id", rideController.startRide);
router.post("/complete/:id", rideController.completeRide);
router.post("/cancel/:id", rideController.cancelRide);
router.post("/pay/:id", rideController.payRide);
router.get("/:id/offers", rideController.getRideOffers);
router.post("/:id/offers", rideController.submitRideOffer);
router.post("/:id/confirm-offer", rideController.confirmRideOffer);
router.post("/negotiate/:id", rideController.negotiateFare);
router.post("/accept-offer/:id", rideController.acceptFare);
router.post("/reject-offer/:id", rideController.rejectFare);
router.get("/:id", rideController.getRide);

module.exports = router;
