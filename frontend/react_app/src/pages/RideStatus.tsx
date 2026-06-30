import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { MapPin, Users, DollarSign } from 'lucide-react';
import { useRideStore } from '../store/rideStore';

export default function RideStatus() {
  const navigate = useNavigate();
  const { activeRide, getActiveRide, loading } = useRideStore();
  const [polling, setPolling] = useState(true);

  useEffect(() => {
    if (!activeRide) {
      navigate('/');
      return;
    }
  }, [activeRide, navigate]);

  useEffect(() => {
    if (!polling) return;

    const interval = setInterval(() => {
      getActiveRide();
    }, 3000);

    return () => clearInterval(interval);
  }, [polling, getActiveRide]);

  if (!activeRide) {
    return (
      <div className="min-h-screen bg-dark flex items-center justify-center">
        <p className="text-gray-400">Loading ride details...</p>
      </div>
    );
  }

  const statusColors: Record<string, string> = {
    REQUESTED: 'bg-blue-500/20 text-blue-400',
    NEGOTIATING: 'bg-yellow-500/20 text-yellow-400',
    ACCEPTED: 'bg-green-500/20 text-green-400',
    STARTED: 'bg-purple-500/20 text-purple-400',
    COMPLETED: 'bg-primary/20 text-primary',
  };

  return (
    <div className="min-h-screen bg-dark p-4">
      <div className="max-w-2xl mx-auto">
        <button
          onClick={() => navigate('/')}
          className="mb-4 text-gray-400 hover:text-primary"
        >
          ← Back
        </button>

        <div className="bg-darkalt rounded-lg border border-primary/20 p-6 space-y-6">
          <div className="flex justify-between items-start">
            <h1 className="text-2xl font-bold">Ride Details</h1>
            <div className={`px-3 py-1 rounded-full text-sm font-semibold ${statusColors[activeRide.status] || ''}`}>
              {activeRide.status}
            </div>
          </div>

          <div className="grid md:grid-cols-2 gap-6">
            <div>
              <div className="space-y-4">
                <div className="flex items-start gap-3">
                  <MapPin className="text-green-400 mt-1 flex-shrink-0" size={20} />
                  <div>
                    <p className="text-gray-400 text-sm">Pickup</p>
                    <p className="font-semibold">{activeRide.pickup.address}</p>
                  </div>
                </div>

                <div className="h-12 border-l-2 border-primary/30 ml-2"></div>

                <div className="flex items-start gap-3">
                  <MapPin className="text-danger mt-1 flex-shrink-0" size={20} />
                  <div>
                    <p className="text-gray-400 text-sm">Dropoff</p>
                    <p className="font-semibold">{activeRide.drop.address}</p>
                  </div>
                </div>
              </div>
            </div>

            <div className="space-y-4">
              <div className="flex items-start gap-3">
                <DollarSign className="text-primary mt-1" size={20} />
                <div>
                  <p className="text-gray-400 text-sm">Estimated Fare</p>
                  <p className="font-semibold text-lg">₹{activeRide.estimatedFare}</p>
                  {activeRide.finalFare && (
                    <p className="text-primary text-sm">Final: ₹{activeRide.finalFare}</p>
                  )}
                </div>
              </div>

              <div className="flex items-start gap-3">
                <Users className="text-primary mt-1" size={20} />
                <div>
                  <p className="text-gray-400 text-sm">Payment Method</p>
                  <p className="font-semibold">{activeRide.paymentMethod}</p>
                </div>
              </div>
            </div>
          </div>

          {activeRide.status === 'REQUESTED' && (
            <div className="bg-yellow-500/10 border border-yellow-500/30 rounded p-4">
              <p className="text-yellow-400">Waiting for driver acceptance...</p>
            </div>
          )}

          {activeRide.status === 'NEGOTIATING' && (
            <div className="bg-blue-500/10 border border-blue-500/30 rounded p-4">
              <p className="text-blue-400">Drivers are submitting offers. Choose the best one!</p>
            </div>
          )}

          {activeRide.status === 'ACCEPTED' && (
            <div className="bg-green-500/10 border border-green-500/30 rounded p-4">
              <p className="text-green-400">Driver accepted! They will arrive shortly.</p>
            </div>
          )}

          {activeRide.status === 'STARTED' && (
            <div className="bg-purple-500/10 border border-purple-500/30 rounded p-4">
              <p className="text-purple-400">Ride in progress. Driver is on the way.</p>
            </div>
          )}

          <button
            onClick={() => setPolling(!polling)}
            className="w-full px-4 py-2 bg-primary/20 text-primary rounded-lg hover:bg-primary/30"
          >
            {polling ? 'Stop Auto-Refresh' : 'Resume Auto-Refresh'}
          </button>
        </div>
      </div>
    </div>
  );
}
