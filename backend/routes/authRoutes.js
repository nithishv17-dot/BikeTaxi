const express = require("express");
const router = express.Router();
const authController = require("../controllers/authController");

router.post("/guest-login", authController.guestLogin);
router.post("/google-login", authController.googleLogin);

module.exports = router;

