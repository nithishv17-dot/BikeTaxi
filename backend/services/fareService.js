const mongoose = require('mongoose');
const Ride = require('../models/Ride');

const DEFAULT_CONFIG = Object.freeze({
  baseFare: 15,
  baseDistanceKm: 1.5,
  perKmRate: 9,
  aboveTenKmRate: 8,
  timeChargePerMinute: 0.3,
  platformFee: 5,
  gstPercent: 5,
  driverEarningsPercent: 85,
  platformCommissionPercent: 15,
});

const FareConfiguration = mongoose.model(
  'FareConfiguration',
  new mongoose.Schema(
    {
      key: { type: String, required: true, unique: true, trim: true },
      value: { type: Number, required: true },
      description: { type: String, default: '' },
    },
    { timestamps: true }
  )
);

const SurgePricing = mongoose.model(
  'SurgePricing',
  new mongoose.Schema(
    {
      name: { type: String, required: true, trim: true },
      multiplier: { type: Number, required: true },
      isActive: { type: Boolean, default: true },
      priority: { type: Number, default: 0 },
    },
    { timestamps: true }
  )
);

const Coupon = mongoose.model(
  'Coupon',
  new mongoose.Schema(
    {
      code: { type: String, required: true, unique: true, trim: true, uppercase: true },
      type: { type: String, enum: ['flat', 'percentage'], required: true },
      value: { type: Number, required: true },
      maxDiscount: { type: Number, default: 0 },
      expiresAt: { type: Date, default: null },
      usageLimit: { type: Number, default: 0 },
      usedCount: { type: Number, default: 0 },
      isActive: { type: Boolean, default: true },
      firstRideOnly: { type: Boolean, default: false },
    },
    { timestamps: true }
  )
);

const RideFare = mongoose.model(
  'RideFare',
  new mongoose.Schema(
    {
      rideId: { type: mongoose.Schema.Types.ObjectId, ref: 'Ride', required: true, unique: true },
      baseFare: { type: Number, default: 0 },
      distanceFare: { type: Number, default: 0 },
      timeFare: { type: Number, default: 0 },
      subtotal: { type: Number, default: 0 },
      surgeMultiplier: { type: Number, default: 1 },
      surgeAmount: { type: Number, default: 0 },
      platformFee: { type: Number, default: 0 },
      gst: { type: Number, default: 0 },
      couponDiscount: { type: Number, default: 0 },
      walletDeduction: { type: Number, default: 0 },
      totalFare: { type: Number, default: 0 },
      customerPays: { type: Number, default: 0 },
      driverEarnings: { type: Number, default: 0 },
      platformCommission: { type: Number, default: 0 },
      breakdown: { type: Object, default: {} },
      status: { type: String, enum: ['calculated', 'applied', 'cancelled'], default: 'calculated' },
    },
    { timestamps: true }
  )
);

const WalletTransaction = mongoose.model(
  'WalletTransaction',
  new mongoose.Schema(
    {
      userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
      rideId: { type: mongoose.Schema.Types.ObjectId, ref: 'Ride', default: null },
      amount: { type: Number, required: true },
      type: { type: String, enum: ['credit', 'debit'], required: true },
      description: { type: String, default: '' },
    },
    { timestamps: true }
  )
);

const DriverPayout = mongoose.model(
  'DriverPayout',
  new mongoose.Schema(
    {
      driverId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
      rideId: { type: mongoose.Schema.Types.ObjectId, ref: 'Ride', required: true },
      amount: { type: Number, required: true },
      status: { type: String, enum: ['pending', 'paid'], default: 'pending' },
    },
    { timestamps: true }
  )
);

const memoryConfig = { ...DEFAULT_CONFIG };
const memoryCoupons = new Map();
const memorySurgePricing = [];

const roundToTwo = (value) => Number((Math.round(value * 100) / 100).toFixed(2));
const isDatabaseConnected = () => mongoose.connection.readyState === 1;

const getConfigValue = async (key, fallback) => {
  if (!isDatabaseConnected()) {
    return memoryConfig[key] ?? fallback;
  }

  const record = await FareConfiguration.findOne({ key }).lean();
  return record ? Number(record.value) : fallback;
};

const ensureConfigDefaults = async () => {
  if (!isDatabaseConnected()) {
    Object.entries(DEFAULT_CONFIG).forEach(([key, value]) => {
      if (memoryConfig[key] === undefined) {
        memoryConfig[key] = value;
      }
    });
    if (!memoryCoupons.has('SAVE20')) {
      memoryCoupons.set('SAVE20', { code: 'SAVE20', type: 'flat', value: 20, maxDiscount: 20, expiresAt: null, usageLimit: 0, usedCount: 0, isActive: true, firstRideOnly: false });
    }
    return;
  }

  const defaults = [
    ['baseFare', DEFAULT_CONFIG.baseFare, 'Base fare'],
    ['baseDistanceKm', DEFAULT_CONFIG.baseDistanceKm, 'Base distance in km'],
    ['perKmRate', DEFAULT_CONFIG.perKmRate, 'Distance rate for 1.5 km to 10 km'],
    ['aboveTenKmRate', DEFAULT_CONFIG.aboveTenKmRate, 'Distance rate above 10 km'],
    ['timeChargePerMinute', DEFAULT_CONFIG.timeChargePerMinute, 'Per-minute ride charge'],
    ['platformFee', DEFAULT_CONFIG.platformFee, 'Platform fee'],
    ['gstPercent', DEFAULT_CONFIG.gstPercent, 'GST percentage'],
    ['driverEarningsPercent', DEFAULT_CONFIG.driverEarningsPercent, 'Driver earnings percentage'],
    ['platformCommissionPercent', DEFAULT_CONFIG.platformCommissionPercent, 'Platform commission percentage'],
  ];

  await Promise.all(defaults.map(([key, value, description]) => FareConfiguration.findOneAndUpdate(
    { key },
    { $setOnInsert: { key, value, description } },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  )));
};

const resolveConfig = async () => ({
  baseFare: await getConfigValue('baseFare', DEFAULT_CONFIG.baseFare),
  baseDistanceKm: await getConfigValue('baseDistanceKm', DEFAULT_CONFIG.baseDistanceKm),
  perKmRate: await getConfigValue('perKmRate', DEFAULT_CONFIG.perKmRate),
  aboveTenKmRate: await getConfigValue('aboveTenKmRate', DEFAULT_CONFIG.aboveTenKmRate),
  timeChargePerMinute: await getConfigValue('timeChargePerMinute', DEFAULT_CONFIG.timeChargePerMinute),
  platformFee: await getConfigValue('platformFee', DEFAULT_CONFIG.platformFee),
  gstPercent: await getConfigValue('gstPercent', DEFAULT_CONFIG.gstPercent),
  driverEarningsPercent: await getConfigValue('driverEarningsPercent', DEFAULT_CONFIG.driverEarningsPercent),
  platformCommissionPercent: await getConfigValue('platformCommissionPercent', DEFAULT_CONFIG.platformCommissionPercent),
});

const calculateDistanceFare = (distanceKm, config) => {
  if (distanceKm <= config.baseDistanceKm) {
    return 0;
  }

  const remainingDistance = distanceKm - config.baseDistanceKm;
  if (distanceKm <= 10) {
    return roundToTwo(remainingDistance * config.perKmRate);
  }

  const firstSegment = 8.5 * config.perKmRate;
  const remainingSegment = distanceKm - 10;
  const secondSegment = remainingSegment * config.aboveTenKmRate;
  return roundToTwo(firstSegment + secondSegment);
};

const calculateCouponDiscount = async (couponCode, subtotal, { firstRideOnly = false } = {}) => {
  if (!couponCode) {
    return { discount: 0, coupon: null };
  }

  if (!isDatabaseConnected()) {
    const coupon = memoryCoupons.get(couponCode.toUpperCase());
    if (!coupon || !coupon.isActive) {
      throw new Error('Invalid coupon');
    }

    const now = new Date();
    if (coupon.expiresAt && coupon.expiresAt < now) {
      throw new Error('Coupon expired');
    }

    if (coupon.usageLimit > 0 && coupon.usedCount >= coupon.usageLimit) {
      throw new Error('Coupon usage limit reached');
    }

    let discount = 0;
    if (coupon.type === 'flat') {
      discount = coupon.value;
    } else if (coupon.type === 'percentage') {
      discount = roundToTwo((subtotal * coupon.value) / 100);
    }

    if (coupon.maxDiscount > 0) {
      discount = Math.min(discount, coupon.maxDiscount);
    }

    return { discount: roundToTwo(Math.max(0, discount)), coupon: { ...coupon } };
  }

  const coupon = await Coupon.findOne({ code: couponCode.toUpperCase(), isActive: true });
  if (!coupon) {
    throw new Error('Invalid coupon');
  }

  if (coupon.firstRideOnly && firstRideOnly) {
    throw new Error('Coupon is only valid for first ride');
  }

  const now = new Date();
  if (coupon.expiresAt && coupon.expiresAt < now) {
    throw new Error('Coupon expired');
  }

  if (coupon.usageLimit > 0 && coupon.usedCount >= coupon.usageLimit) {
    throw new Error('Coupon usage limit reached');
  }

  let discount = 0;
  if (coupon.type === 'flat') {
    discount = coupon.value;
  } else if (coupon.type === 'percentage') {
    discount = roundToTwo((subtotal * coupon.value) / 100);
  }

  if (coupon.maxDiscount > 0) {
    discount = Math.min(discount, coupon.maxDiscount);
  }

  return { discount: roundToTwo(Math.max(0, discount)), coupon };
};

const applyCoupon = async (couponCode, subtotal, options = {}) => {
  const { discount, coupon } = await calculateCouponDiscount(couponCode, subtotal, options);
  if (coupon) {
    if (isDatabaseConnected()) {
      coupon.usedCount += 1;
      await coupon.save();
    } else {
      const memoryCoupon = memoryCoupons.get(coupon.code.toUpperCase());
      if (memoryCoupon) {
        memoryCoupon.usedCount += 1;
        memoryCoupons.set(memoryCoupon.code.toUpperCase(), memoryCoupon);
      }
    }
  }
  return { couponDiscount: discount, coupon };
};

const calculateFare = async ({
  distanceKm,
  durationMinutes,
  surgeMultiplier = 1,
  couponCode,
  walletAmount = 0,
  rideId = null,
  firstRideOnly = false,
}) => {
  if (distanceKm === undefined || durationMinutes === undefined) {
    throw new Error('Distance and duration are required');
  }

  if (Number(distanceKm) < 0) {
    throw new Error('Distance cannot be negative');
  }

  if (Number(durationMinutes) < 0) {
    throw new Error('Duration cannot be negative');
  }

  const numericDistance = Number(distanceKm);
  const numericDuration = Number(durationMinutes);
  const numericSurge = Number(surgeMultiplier ?? 1);
  const numericWallet = Number(walletAmount ?? 0);

  if (!Number.isFinite(numericDistance) || !Number.isFinite(numericDuration)) {
    throw new Error('Distance and duration must be numeric');
  }

  await ensureConfigDefaults();
  const config = await resolveConfig();

  const baseFare = roundToTwo(config.baseFare);
  const distanceFare = roundToTwo(calculateDistanceFare(numericDistance, config));
  const timeFare = roundToTwo(numericDuration * config.timeChargePerMinute);
  const subtotal = roundToTwo(baseFare + distanceFare + timeFare);
  const effectiveSurgeMultiplier = Number.isFinite(numericSurge) && numericSurge > 0 ? numericSurge : 1;
  const surgeAmount = roundToTwo(subtotal * (effectiveSurgeMultiplier - 1));
  const surgeTotal = roundToTwo(subtotal + surgeAmount);
  const platformFee = roundToTwo(config.platformFee);
  const fareBeforeGst = roundToTwo(surgeTotal + platformFee);
  const gst = roundToTwo((fareBeforeGst * config.gstPercent) / 100);
  const totalBeforeCoupon = roundToTwo(fareBeforeGst + gst);

  const { couponDiscount } = await applyCoupon(couponCode, totalBeforeCoupon, { firstRideOnly });
  const discountedTotal = roundToTwo(Math.max(0, totalBeforeCoupon - couponDiscount));
  const walletDeduction = roundToTwo(Math.min(numericWallet, discountedTotal));
  const finalTotal = roundToTwo(Math.max(0, discountedTotal - walletDeduction));

  const driverEarnings = roundToTwo(finalTotal * (config.driverEarningsPercent / 100));
  const platformCommission = roundToTwo(finalTotal * (config.platformCommissionPercent / 100));

  const breakdown = {
    baseFare,
    distanceFare,
    timeFare,
    subtotal,
    surgeMultiplier: effectiveSurgeMultiplier,
    surgeAmount,
    platformFee,
    gst,
    couponDiscount,
    walletDeduction,
    totalFare: finalTotal,
    customerPays: finalTotal,
    driverEarnings,
    platformCommission,
  };

  let record = null;
  if (isDatabaseConnected()) {
    record = await RideFare.findOneAndUpdate(
      { rideId },
      { $set: { ...breakdown, rideId, breakdown, status: 'calculated' } },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
  }

  if (rideId && isDatabaseConnected()) {
    const ride = await Ride.findById(rideId);
    if (ride) {
      await WalletTransaction.create({
        userId: ride.userId,
        rideId,
        amount: walletDeduction,
        type: 'debit',
        description: 'Wallet deduction for ride fare',
      });
    }
  }

  return { ...breakdown, recordId: record?._id || null };
};

module.exports = {
  calculateFare,
  applyCoupon,
  calculateCouponDiscount,
  ensureConfigDefaults,
  FareConfiguration,
  SurgePricing,
  Coupon,
  RideFare,
  WalletTransaction,
  DriverPayout,
  DEFAULT_CONFIG,
  roundToTwo,
  memoryConfig,
  memoryCoupons,
  memorySurgePricing,
};
