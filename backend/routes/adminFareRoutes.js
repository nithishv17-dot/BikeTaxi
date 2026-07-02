const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { FareConfiguration, SurgePricing, Coupon, memoryConfig, memoryCoupons, memorySurgePricing } = require('../services/fareService');

router.use(authMiddleware);

router.get('/config', async (_req, res) => {
  try {
    if (FareConfiguration.db && FareConfiguration.db.readyState === 1) {
      const configs = await FareConfiguration.find({}).lean();
      return res.status(200).json({ message: 'Pricing configuration fetched', config: configs });
    }

    return res.status(200).json({ message: 'Pricing configuration fetched', config: Object.entries(memoryConfig).map(([key, value]) => ({ key, value })) });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
});

router.post('/config', async (req, res) => {
  try {
    const { key, value } = req.body;
    if (!key || value === undefined) {
      return res.status(400).json({ message: 'Key and value are required' });
    }

    if (FareConfiguration.db && FareConfiguration.db.readyState === 1) {
      const updated = await FareConfiguration.findOneAndUpdate(
        { key },
        { $set: { value: Number(value) } },
        { upsert: true, new: true }
      );
      return res.status(200).json({ message: 'Configuration updated', config: updated });
    }

    memoryConfig[key] = Number(value);
    return res.status(200).json({ message: 'Configuration updated', config: { key, value: memoryConfig[key] } });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
});

router.post('/surge', async (req, res) => {
  try {
    if (SurgePricing.db && SurgePricing.db.readyState === 1) {
      const surge = new SurgePricing(req.body);
      await surge.save();
      return res.status(201).json({ message: 'Surge pricing created', surge });
    }

    const surge = { ...req.body, createdAt: new Date().toISOString() };
    memorySurgePricing.push(surge);
    return res.status(201).json({ message: 'Surge pricing created', surge });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
});

router.post('/coupon', async (req, res) => {
  try {
    if (Coupon.db && Coupon.db.readyState === 1) {
      const coupon = new Coupon(req.body);
      await coupon.save();
      return res.status(201).json({ message: 'Coupon created', coupon });
    }

    const coupon = { ...req.body, code: String(req.body.code || '').toUpperCase() };
    memoryCoupons.set(coupon.code, coupon);
    return res.status(201).json({ message: 'Coupon created', coupon });
  } catch (error) {
    return res.status(500).json({ message: error.message });
  }
});

module.exports = router;
