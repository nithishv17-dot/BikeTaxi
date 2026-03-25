const express = require("express");
const router = express.Router();
const rideController = require("../controllers/rideController");

router.post("/request", rideController.requestRide);
router.get("/user/:userId/history", rideController.getUserRides);
router.post("/accept/:id", rideController.acceptRide);
router.post("/start/:id", rideController.startRide);
router.post("/complete/:id", rideController.completeRide);
router.post("/cancel/:id", rideController.cancelRide);
router.get("/:id", rideController.getRide);

module.exports = router;