import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { MapPin, LogOut } from 'lucide-react';
import { useAuthStore } from '../store/authStore';
import { useRideStore, LocationData } from '../store/rideStore';

export default function Home() {
  const navigate = useNavigate();
  const { user, logout } = useAuthStore();
  const { activeRide, requestRide, getActiveRide, loading } = useRideStore();
  const [pickupAddress, setPickupAddress] = useState('');
  const [dropAddress, setDropAddress] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('CASH');

  useEffect(() => {
    if (!user) {
      navigate('/login');
      return;
    }
    getActiveRide();
  }, [user, navigate, getActiveRide]);

  const handleRequestRide = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pickupAddress || !dropAddress) {
      alert('Please fill in all fields');
      return;
    }

    const pickup: LocationData = {
      address: pickupAddress,
      latitude: 12.9716,
      longitude: 77.5946,
    };

    const drop: LocationData = {
      address: dropAddress,
      latitude: 12.9352,
      longitude: 77.6245,
    };

    try {
      await requestRide(pickup, drop, paymentMethod);
      navigate('/ride-status');
    } catch (err) {
      console.error('Failed to request ride:', err);
    }
  };

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  return (
    <div className="min-h-screen bg-dark">
      <header className="bg-darkalt border-b border-primary/20 p-4 flex justify-between items-center">
        <div>
          <h1 className="text-xl font-bold text-primary">BikeTaxi</h1>
          <p className="text-sm text-gray-400">{user?.name}</p>
        </div>
        <button
          onClick={handleLogout}
          className="flex items-center gap-2 px-4 py-2 bg-danger/20 text-danger rounded-lg hover:bg-danger/30"
        >
          <LogOut size={18} />
          Logout
        </button>
      </header>

      <main className="p-4 max-w-2xl mx-auto">
        {activeRide ? (
          <div className="bg-darkalt rounded-lg border border-primary/20 p-6">
            <h2 className="text-xl font-bold mb-4">Your Active Ride</h2>
            <div className="space-y-4">
              <div>
                <p className="text-gray-400 text-sm">Pickup</p>
                <p className="font-semibold">{activeRide.pickup.address}</p>
              </div>
              <div>
                <p className="text-gray-400 text-sm">Dropoff</p>
                <p className="font-semibold">{activeRide.drop.address}</p>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-gray-400 text-sm">Status</p>
                  <p className="font-semibold text-primary">{activeRide.status}</p>
                </div>
                <div>
                  <p className="text-gray-400 text-sm">Estimated Fare</p>
                  <p className="font-semibold">₹{activeRide.estimatedFare}</p>
                </div>
              </div>
              <button
                onClick={() => navigate('/ride-status')}
                className="w-full bg-primary text-dark font-semibold py-2 rounded-lg hover:bg-primary/90"
              >
                View Details
              </button>
            </div>
          </div>
        ) : (
          <div className="bg-darkalt rounded-lg border border-primary/20 p-6">
            <h2 className="text-xl font-bold mb-6">Request a Ride</h2>

            <form onSubmit={handleRequestRide} className="space-y-6">
              <div>
                <label className="block text-sm font-medium mb-2 flex items-center gap-2">
                  <MapPin size={18} /> Pickup Location
                </label>
                <input
                  type="text"
                  value={pickupAddress}
                  onChange={(e) => setPickupAddress(e.target.value)}
                  placeholder="Where are you?"
                  className="w-full px-4 py-2 bg-dark border border-gray-600 rounded-lg focus:outline-none focus:border-primary"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium mb-2 flex items-center gap-2">
                  <MapPin size={18} /> Dropoff Location
                </label>
                <input
                  type="text"
                  value={dropAddress}
                  onChange={(e) => setDropAddress(e.target.value)}
                  placeholder="Where to?"
                  className="w-full px-4 py-2 bg-dark border border-gray-600 rounded-lg focus:outline-none focus:border-primary"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium mb-2">Payment Method</label>
                <select
                  value={paymentMethod}
                  onChange={(e) => setPaymentMethod(e.target.value)}
                  className="w-full px-4 py-2 bg-dark border border-gray-600 rounded-lg focus:outline-none focus:border-primary"
                >
                  <option value="CASH">Cash</option>
                  <option value="UPI">UPI</option>
                  <option value="CARD">Card</option>
                </select>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full bg-primary text-dark font-semibold py-3 rounded-lg hover:bg-primary/90 disabled:opacity-50"
              >
                {loading ? 'Requesting...' : 'Request Ride'}
              </button>
            </form>
          </div>
        )}
      </main>
    </div>
  );
}
