const express = require("express");
const router = express.Router();
const driverController = require("../controllers/driverController");
const authMiddleware = require("../middleware/authMiddleware");

router.post("/list", authMiddleware, driverController.getDrivers);
router.post("/toggle", authMiddleware, driverController.toggleAvailability);
router.post("/toggle/:id", authMiddleware, driverController.toggleAvailability);
router.get("/status", authMiddleware, driverController.getDriverStatus);
router.get("/status/:id", authMiddleware, driverController.getDriverStatus);
router.post("/mock-nearby", driverController.mockNearby);

module.exports = router;
