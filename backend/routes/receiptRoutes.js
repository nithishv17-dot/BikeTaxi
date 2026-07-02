const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { calculateFare } = require('../services/fareService');

router.post('/receipt', authMiddleware, async (req, res) => {
  try {
    const fare = await calculateFare({
      distanceKm: req.body.distanceKm,
      durationMinutes: req.body.durationMinutes,
      surgeMultiplier: req.body.surgeMultiplier,
      couponCode: req.body.couponCode,
      walletAmount: req.body.walletAmount,
    });

    return res.status(200).json({
      message: 'Receipt prepared successfully',
      receipt: {
        rideDistance: `${req.body.distanceKm} km`,
        rideDuration: `${req.body.durationMinutes} min`,
        baseFare: fare.baseFare,
        distanceFare: fare.distanceFare,
        timeFare: fare.timeFare,
        surge: fare.surgeAmount,
        platformFee: fare.platformFee,
        gst: fare.gst,
        couponDiscount: fare.couponDiscount,
        walletDeduction: fare.walletDeduction,
        grandTotal: fare.totalFare,
        customerPaid: fare.customerPays,
        driverEarnings: fare.driverEarnings,
        platformEarnings: fare.platformCommission,
      },
    });
  } catch (error) {
    return res.status(400).json({ message: error.message });
  }
});

module.exports = router;
