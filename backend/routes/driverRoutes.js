const express = require("express");
const router = express.Router();
const driverController = require("../controllers/driverController");

router.post("/list", driverController.getDrivers);
router.post("/toggle/:id", driverController.toggleAvailability);

module.exports = router;