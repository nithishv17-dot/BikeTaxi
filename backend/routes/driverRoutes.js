const express = require("express");
const router = express.Router();
const driverController = require("../controllers/driverController");
const authMiddleware = require("../middleware/authMiddleware");

router.post("/list", authMiddleware, driverController.getDrivers);
router.post("/toggle/:id", authMiddleware, driverController.toggleAvailability);

module.exports = router;
