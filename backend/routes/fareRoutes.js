const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { calculateFare } = require('../services/fareService');

router.post('/calculate', authMiddleware, async (req, res) => {
  try {
    const result = await calculateFare({
      distanceKm: req.body.distanceKm,
      durationMinutes: req.body.durationMinutes,
      surgeMultiplier: req.body.surgeMultiplier,
      couponCode: req.body.couponCode,
      walletAmount: req.body.walletAmount,
      rideId: req.body.rideId || null,
      firstRideOnly: Boolean(req.body.firstRideOnly),
    });

    return res.status(200).json({
      message: 'Fare calculated successfully',
      fare: result,
    });
  } catch (error) {
    return res.status(400).json({ message: error.message });
  }
});

module.exports = router;
