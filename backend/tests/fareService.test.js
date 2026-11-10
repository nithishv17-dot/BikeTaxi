const test = require('node:test');
const assert = require('node:assert/strict');

const { calculateFare } = require('../services/fareService');

test('calculates a normal fare with base, distance, time, platform fee and GST', async () => {
  const result = await calculateFare({
    distanceKm: 2,
    durationMinutes: 10,
    surgeMultiplier: 1,
    walletAmount: 0,
  });

  assert.equal(result.baseFare, 15);
  assert.equal(result.distanceFare, 4.5);
  assert.equal(result.timeFare, 3);
  assert.equal(result.subtotal, 22.5);
  assert.equal(result.surgeMultiplier, 1);
  assert.equal(result.surgeAmount, 0);
  assert.equal(result.platformFee, 5);
  assert.equal(result.gst, 1.375);
  assert.equal(result.totalFare, 28.875);
  assert.equal(result.customerPays, 28.875);
  assert.equal(result.driverEarnings, 24.54375);
  assert.equal(result.platformCommission, 4.33125);
});

test('applies coupon and wallet deductions correctly', async () => {
  const result = await calculateFare({
    distanceKm: 6,
    durationMinutes: 12,
    surgeMultiplier: 1.2,
    couponCode: 'SAVE20',
    walletAmount: 10,
  });

  assert.equal(result.couponDiscount, 20);
  assert.equal(result.walletDeduction, 10);
  assert.equal(result.customerPays, 0);
});

test('rejects invalid coupons', async () => {
  await assert.rejects(() => calculateFare({
    distanceKm: 2,
    durationMinutes: 10,
    couponCode: 'INVALID',
  }), /Invalid coupon/);
});

test('rejects negative distance or duration', async () => {
  await assert.rejects(() => calculateFare({ distanceKm: -1, durationMinutes: 10 }), /distance/i);
  await assert.rejects(() => calculateFare({ distanceKm: 2, durationMinutes: -1 }), /duration/i);
});
