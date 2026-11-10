import { useState, useEffect } from "react";
import { RideGoMap } from "@/components/map/RideGoMap";
import type { MapPoint, MapDriver } from "@/components/map/RideGoMap";
import { Card } from "@/components/ui/card";
import { RoutingService } from "@/services/routingService";
import type { RouteResult } from "@/services/routingService";
import { PhotonService } from "@/services/photonService";
import type { PhotonPlace } from "@/services/photonService";
import { LocationService } from "@/services/locationService";
import { SocketService } from "@/services/socketService";
import type { DriverLocationUpdate } from "@/services/socketService";
import {
  Bike,
  MapPin,
  Flag,
  Navigation,
  Crosshair,
  Moon,
  Sun,
  Clock,
  Gauge,
  IndianRupee,
  CheckCircle2,
  X,
  ArrowRight,
  Sparkles,
  Loader2,
} from "lucide-react";

export function App() {
  const [theme, setTheme] = useState<"dark" | "light">("dark");
  const [userLocation, setUserLocation] = useState<MapPoint | null>(null);
  const [pickup, setPickup] = useState<MapPoint | null>(null);
  const [drop, setDrop] = useState<MapPoint | null>(null);
  const [routeResult, setRouteResult] = useState<RouteResult | null>(null);
  const [isRouting, setIsRouting] = useState(false);

  // Search input states
  const [pickupInput, setPickupInput] = useState("");
  const [dropInput, setDropInput] = useState("");
  const [pickupSuggestions, setPickupSuggestions] = useState<PhotonPlace[]>([]);
  const [dropSuggestions, setDropSuggestions] = useState<PhotonPlace[]>([]);
  const [isSearchingPickup, setIsSearchingPickup] = useState(false);
  const [isSearchingDrop, setIsSearchingDrop] = useState(false);

  // Map tap selection mode ("pickup" | "drop" | null)
  const [tapMode, setTapMode] = useState<"pickup" | "drop" | null>(null);

  // Drivers
  const [drivers, setDrivers] = useState<MapDriver[]>([
    {
      driverId: "driver_1",
      name: "Suresh (Pulsar 150)",
      phone: "+91 98765 43210",
      lat: 11.0185,
      lng: 76.9625,
      heading: 45,
      available: true,
    },
    {
      driverId: "driver_2",
      name: "Karthik (Splendor+)",
      phone: "+91 98765 11223",
      lat: 11.0125,
      lng: 76.9515,
      heading: 180,
      available: true,
    },
    {
      driverId: "driver_3",
      name: "Arun (FZ-S v3)",
      phone: "+91 98765 99887",
      lat: 11.0235,
      lng: 76.9585,
      heading: 270,
      available: true,
    },
  ]);

  const [bookingConfirmed, setBookingConfirmed] = useState(false);

  // Toggle Theme
  const toggleTheme = () => {
    const next = theme === "dark" ? "light" : "dark";
    setTheme(next);
    if (next === "dark") {
      document.documentElement.classList.add("dark");
    } else {
      document.documentElement.classList.remove("dark");
    }
  };

  // Sync theme class on mount
  useEffect(() => {
    document.documentElement.classList.add("dark");
  }, []);

  // Initialize HTML5 Geolocation
  useEffect(() => {
    LocationService.getCurrentPosition().then(async (pos) => {
      if (pos) {
        const place = await PhotonService.reverseGeocode(pos.lat, pos.lng);
        const userPt: MapPoint = {
          lat: pos.lat,
          lng: pos.lng,
          address: place?.address || "Current Live Location",
          name: "My Location",
        };
        setUserLocation(userPt);

        // By default, set current location as initial pickup
        setPickup(userPt);
        setPickupInput(userPt.address || "My Location");

        // Spawn mock nearby drivers relative to current location
        setDrivers([
          {
            driverId: "driver_live_1",
            name: "Vignesh (Apache RTR)",
            phone: "+91 94432 12345",
            lat: pos.lat + 0.003,
            lng: pos.lng + 0.004,
            heading: 60,
            available: true,
          },
          {
            driverId: "driver_live_2",
            name: "Rajesh (Honda Shine)",
            phone: "+91 94432 67890",
            lat: pos.lat - 0.002,
            lng: pos.lng - 0.003,
            heading: 210,
            available: true,
          },
          {
            driverId: "driver_live_3",
            name: "Manikandan (Activa 6G)",
            phone: "+91 94432 55443",
            lat: pos.lat + 0.004,
            lng: pos.lng - 0.002,
            heading: 130,
            available: true,
          },
        ]);
      }
    });
  }, []);

  // Connect Socket.io for live driver tracking
  useEffect(() => {
    SocketService.init();

    const handleDriverLocation = (update: DriverLocationUpdate) => {
      setDrivers((prev) => {
        const index = prev.findIndex((d) => d.driverId === update.driverId);
        if (index >= 0) {
          const updated = [...prev];
          updated[index] = {
            ...updated[index],
            lat: update.lat,
            lng: update.lng,
            heading: update.heading ?? updated[index].heading,
          };
          return updated;
        } else {
          return [
            ...prev,
            {
              driverId: update.driverId,
              lat: update.lat,
              lng: update.lng,
              heading: update.heading,
              name: `Driver #${update.driverId.slice(-4)}`,
              available: true,
            },
          ];
        }
      });
    };

    SocketService.onDriverLocationUpdated(handleDriverLocation);

    return () => {
      SocketService.offDriverLocationUpdated(handleDriverLocation);
    };
  }, []);

  // Debounced Photon search for Pickup
  useEffect(() => {
    if (!pickupInput.trim() || (pickup && pickup.address === pickupInput)) {
      setPickupSuggestions([]);
      return;
    }

    const timer = setTimeout(async () => {
      setIsSearchingPickup(true);
      const results = await PhotonService.searchPlaces(
        pickupInput,
        userLocation?.lat,
        userLocation?.lng
      );
      setPickupSuggestions(results);
      setIsSearchingPickup(false);
    }, 350);

    return () => clearTimeout(timer);
  }, [pickupInput, pickup, userLocation]);

  // Debounced Photon search for Drop
  useEffect(() => {
    if (!dropInput.trim() || (drop && drop.address === dropInput)) {
      setDropSuggestions([]);
      return;
    }

    const timer = setTimeout(async () => {
      setIsSearchingDrop(true);
      const results = await PhotonService.searchPlaces(
        dropInput,
        pickup?.lat || userLocation?.lat,
        pickup?.lng || userLocation?.lng
      );
      setDropSuggestions(results);
      setIsSearchingDrop(false);
    }, 350);

    return () => clearTimeout(timer);
  }, [dropInput, drop, pickup, userLocation]);

  // Calculate OSRM route when both pickup and drop are set
  useEffect(() => {
    if (!pickup || !drop) {
      setRouteResult(null);
      return;
    }

    setIsRouting(true);
    RoutingService.getRoute(pickup.lat, pickup.lng, drop.lat, drop.lng).then(
      (result) => {
        setRouteResult(result);
        setIsRouting(false);
      }
    );
  }, [pickup, drop]);

  // Handle Tap-to-Place on MapLibre Canvas
  const handleMapClick = async ({ lat, lng }: { lat: number; lng: number }) => {
    const place = await PhotonService.reverseGeocode(lat, lng);
    const point: MapPoint = {
      lat,
      lng,
      address: place?.address || `Coordinates (${lat.toFixed(4)}, ${lng.toFixed(4)})`,
      name: place?.name || "Selected Location",
    };

    if (tapMode === "pickup" || (!pickup && !drop)) {
      setPickup(point);
      setPickupInput(point.address || "");
      setTapMode(null);
    } else {
      setDrop(point);
      setDropInput(point.address || "");
      setTapMode(null);
    }
  };

  // Calculate Estimated Fare (Base ₹25 + ₹12/km)
  const estimatedFare = routeResult
    ? Math.max(30, Math.round(25 + routeResult.distanceKm * 12))
    : 0;

  return (
    <div className="min-h-screen bg-background text-foreground flex flex-col font-sans transition-colors duration-300">
      {/* Top Navigation Bar */}
      <header className="border-b border-border/50 bg-card/80 backdrop-blur-md sticky top-0 z-40 px-4 lg:px-8 py-3.5 flex items-center justify-between shadow-xs">
        <div className="flex items-center gap-3">
          <div className="flex items-center justify-center w-10 h-10 rounded-xl bg-primary text-primary-foreground shadow-md shadow-primary/20">
            <Bike className="w-6 h-6 stroke-[2.5]" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-xl font-extrabold tracking-tight">RideGo</h1>
              <span className="text-[10px] uppercase font-bold tracking-wider px-2 py-0.5 rounded-full bg-primary/15 text-primary border border-primary/25">
                Bike Taxi GIS
              </span>
            </div>
            <p className="text-xs text-muted-foreground hidden sm:block">
              Powered by @mapcn/map • MapLibre GL • OSRM • Komoot Photon
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          {/* Active Drivers Counter */}
          <div className="hidden sm:flex items-center gap-2 bg-secondary/80 border border-border/60 px-3 py-1.5 rounded-full text-xs font-semibold">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
            </span>
            <span>{drivers.length} Captains Live</span>
          </div>

          {/* Theme Toggle Button */}
          <button
            onClick={toggleTheme}
            className="p-2.5 rounded-xl border border-border/60 bg-secondary/70 hover:bg-secondary text-foreground transition-all cursor-pointer shadow-xs"
            title="Toggle Light/Dark Theme"
          >
            {theme === "dark" ? (
              <Sun className="w-4 h-4 text-amber-400" />
            ) : (
              <Moon className="w-4 h-4 text-slate-700" />
            )}
          </button>
        </div>
      </header>

      {/* Main App Grid */}
      <main className="flex-1 p-4 lg:p-6 grid grid-cols-1 lg:grid-cols-12 gap-6 max-w-7xl mx-auto w-full">
        {/* Left Side: Booking & Route Form */}
        <div className="lg:col-span-5 flex flex-col gap-4">
          <Card className="p-5 border-border/60 bg-card/95 shadow-xl rounded-2xl flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <h2 className="text-base font-bold flex items-center gap-2">
                <Navigation className="w-4 h-4 text-primary" />
                Book Fast Bike Ride
              </h2>
              <span className="text-xs text-muted-foreground font-medium">
                Tap anywhere on map to pin
              </span>
            </div>

            {/* Pickup Input Field */}
            <div className="relative">
              <label className="text-xs font-bold uppercase tracking-wider text-muted-foreground flex items-center justify-between mb-1.5">
                <span className="flex items-center gap-1.5 text-emerald-500 font-semibold">
                  <MapPin className="w-3.5 h-3.5" /> Pickup Point
                </span>
                {userLocation && (
                  <button
                    onClick={() => {
                      setPickup(userLocation);
                      setPickupInput(userLocation.address || "My Location");
                    }}
                    className="text-[11px] text-primary hover:underline flex items-center gap-1 font-semibold cursor-pointer"
                  >
                    <Crosshair className="w-3 h-3" /> Use GPS
                  </button>
                )}
              </label>
              <div className="relative flex items-center">
                <input
                  type="text"
                  value={pickupInput}
                  onChange={(e) => setPickupInput(e.target.value)}
                  placeholder="Enter pickup location (Komoot Photon search)..."
                  className="w-full bg-secondary/70 border border-border/70 rounded-xl px-3.5 py-2.5 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-primary/40 focus:border-primary pr-9"
                />
                {isSearchingPickup && (
                  <Loader2 className="absolute right-8 w-4 h-4 animate-spin text-primary" />
                )}
                {pickupInput && (
                  <button
                    onClick={() => {
                      setPickup(null);
                      setPickupInput("");
                    }}
                    className="absolute right-2.5 text-muted-foreground hover:text-foreground cursor-pointer"
                  >
                    <X className="w-4 h-4" />
                  </button>
                )}
              </div>

              {/* Pickup Suggestions Dropdown */}
              {pickupSuggestions.length > 0 && (
                <div className="absolute left-0 right-0 top-full mt-1.5 z-50 bg-popover text-popover-foreground rounded-xl border border-border shadow-2xl overflow-hidden max-h-56 overflow-y-auto">
                  {pickupSuggestions.map((item) => (
                    <button
                      key={item.placeId}
                      onClick={() => {
                        setPickup({
                          lat: item.lat,
                          lng: item.lng,
                          address: item.address,
                          name: item.name,
                        });
                        setPickupInput(item.address);
                        setPickupSuggestions([]);
                      }}
                      className="w-full text-left px-3.5 py-2.5 hover:bg-secondary/80 border-b border-border/40 last:border-0 flex items-start gap-2.5 transition-colors cursor-pointer"
                    >
                      <MapPin className="w-4 h-4 text-emerald-500 shrink-0 mt-0.5" />
                      <div>
                        <p className="text-xs font-bold text-foreground line-clamp-1">
                          {item.name}
                        </p>
                        <p className="text-[11px] text-muted-foreground line-clamp-1">
                          {item.address}
                        </p>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Drop-off Destination Input Field */}
            <div className="relative">
              <label className="text-xs font-bold uppercase tracking-wider text-muted-foreground flex items-center gap-1.5 text-rose-500 font-semibold mb-1.5">
                <Flag className="w-3.5 h-3.5" /> Drop-off Destination
              </label>
              <div className="relative flex items-center">
                <input
                  type="text"
                  value={dropInput}
                  onChange={(e) => setDropInput(e.target.value)}
                  placeholder="Where are you heading to?..."
                  className="w-full bg-secondary/70 border border-border/70 rounded-xl px-3.5 py-2.5 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-rose-500/40 focus:border-rose-500 pr-9"
                />
                {isSearchingDrop && (
                  <Loader2 className="absolute right-8 w-4 h-4 animate-spin text-rose-500" />
                )}
                {dropInput && (
                  <button
                    onClick={() => {
                      setDrop(null);
                      setDropInput("");
                    }}
                    className="absolute right-2.5 text-muted-foreground hover:text-foreground cursor-pointer"
                  >
                    <X className="w-4 h-4" />
                  </button>
                )}
              </div>

              {/* Drop Suggestions Dropdown */}
              {dropSuggestions.length > 0 && (
                <div className="absolute left-0 right-0 top-full mt-1.5 z-50 bg-popover text-popover-foreground rounded-xl border border-border shadow-2xl overflow-hidden max-h-56 overflow-y-auto">
                  {dropSuggestions.map((item) => (
                    <button
                      key={item.placeId}
                      onClick={() => {
                        setDrop({
                          lat: item.lat,
                          lng: item.lng,
                          address: item.address,
                          name: item.name,
                        });
                        setDropInput(item.address);
                        setDropSuggestions([]);
                      }}
                      className="w-full text-left px-3.5 py-2.5 hover:bg-secondary/80 border-b border-border/40 last:border-0 flex items-start gap-2.5 transition-colors cursor-pointer"
                    >
                      <Flag className="w-4 h-4 text-rose-500 shrink-0 mt-0.5" />
                      <div>
                        <p className="text-xs font-bold text-foreground line-clamp-1">
                          {item.name}
                        </p>
                        <p className="text-[11px] text-muted-foreground line-clamp-1">
                          {item.address}
                        </p>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Quick Tap-to-Place Mode Switches */}
            <div className="flex items-center gap-2 pt-1">
              <button
                onClick={() => setTapMode(tapMode === "pickup" ? null : "pickup")}
                className={`flex-1 py-1.5 px-3 rounded-xl border text-xs font-semibold flex items-center justify-center gap-1.5 transition-all cursor-pointer ${
                  tapMode === "pickup"
                    ? "bg-emerald-600 text-white border-emerald-500 shadow-md shadow-emerald-600/25 ring-2 ring-emerald-500/40"
                    : "bg-secondary/60 hover:bg-secondary border-border/60 text-muted-foreground"
                }`}
              >
                <MapPin className="w-3.5 h-3.5" />
                {tapMode === "pickup" ? "Tap Map to Place Pickup" : "Pin Pickup on Map"}
              </button>

              <button
                onClick={() => setTapMode(tapMode === "drop" ? null : "drop")}
                className={`flex-1 py-1.5 px-3 rounded-xl border text-xs font-semibold flex items-center justify-center gap-1.5 transition-all cursor-pointer ${
                  tapMode === "drop"
                    ? "bg-rose-600 text-white border-rose-500 shadow-md shadow-rose-600/25 ring-2 ring-rose-500/40"
                    : "bg-secondary/60 hover:bg-secondary border-border/60 text-muted-foreground"
                }`}
              >
                <Flag className="w-3.5 h-3.5" />
                {tapMode === "drop" ? "Tap Map to Place Drop" : "Pin Drop on Map"}
              </button>
            </div>
          </Card>

          {/* OSRM Route Loading State */}
          {isRouting && (
            <Card className="p-4 border-primary/30 bg-primary/5 dark:bg-primary/10 rounded-2xl flex items-center justify-center gap-2.5 text-sm font-semibold text-primary animate-pulse">
              <Loader2 className="w-4 h-4 animate-spin" />
              <span>Calculating fastest road path with OSRM...</span>
            </Card>
          )}

          {/* OSRM Route Summary & Fare Card */}
          {routeResult && (
            <Card className="p-5 border-primary/30 bg-primary/5 dark:bg-primary/10 shadow-lg rounded-2xl flex flex-col gap-4 animate-in fade-in slide-in-from-bottom-2 duration-300">
              <div className="flex items-center justify-between border-b border-primary/20 pb-3">
                <span className="text-xs font-bold uppercase tracking-wider text-primary flex items-center gap-1.5">
                  <Sparkles className="w-4 h-4" /> OSRM Road Route Found
                </span>
                <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
                  Fastest Road Path
                </span>
              </div>

              <div className="grid grid-cols-3 gap-2 text-center">
                <div className="bg-card/70 border border-border/60 p-2.5 rounded-xl">
                  <div className="flex items-center justify-center text-muted-foreground mb-1">
                    <Gauge className="w-4 h-4 text-primary" />
                  </div>
                  <p className="text-lg font-black">{routeResult.distanceKm} km</p>
                  <p className="text-[10px] text-muted-foreground uppercase font-semibold">
                    Distance
                  </p>
                </div>

                <div className="bg-card/70 border border-border/60 p-2.5 rounded-xl">
                  <div className="flex items-center justify-center text-muted-foreground mb-1">
                    <Clock className="w-4 h-4 text-amber-500" />
                  </div>
                  <p className="text-lg font-black">{routeResult.durationMinutes} mins</p>
                  <p className="text-[10px] text-muted-foreground uppercase font-semibold">
                    ETA Duration
                  </p>
                </div>

                <div className="bg-card/70 border border-border/60 p-2.5 rounded-xl">
                  <div className="flex items-center justify-center text-muted-foreground mb-1">
                    <IndianRupee className="w-4 h-4 text-emerald-500" />
                  </div>
                  <p className="text-lg font-black text-emerald-600 dark:text-emerald-400">
                    ₹{estimatedFare}
                  </p>
                  <p className="text-[10px] text-muted-foreground uppercase font-semibold">
                    Fixed Fare
                  </p>
                </div>
              </div>

              {/* Ride Request Action Button */}
              <button
                onClick={() => setBookingConfirmed(true)}
                className="w-full py-3 px-4 bg-primary hover:bg-primary/90 text-primary-foreground font-bold rounded-xl shadow-lg shadow-primary/25 flex items-center justify-center gap-2 transition-transform active:scale-98 cursor-pointer"
              >
                <span>Request RideGo Captain (₹{estimatedFare})</span>
                <ArrowRight className="w-4 h-4" />
              </button>
            </Card>
          )}

          {/* Booking Confirmation Toast */}
          {bookingConfirmed && (
            <div className="p-4 rounded-xl bg-emerald-500/15 border border-emerald-500/40 text-emerald-800 dark:text-emerald-200 flex items-center justify-between gap-3 shadow-md animate-in fade-in duration-200">
              <div className="flex items-center gap-2.5">
                <CheckCircle2 className="w-5 h-5 text-emerald-500 shrink-0" />
                <div>
                  <p className="text-xs font-bold">Ride Requested Successfully!</p>
                  <p className="text-[11px] opacity-90">
                    Notifying nearby {drivers.length} captains via Socket.io channel.
                  </p>
                </div>
              </div>
              <button
                onClick={() => setBookingConfirmed(false)}
                className="text-xs font-bold underline opacity-80 hover:opacity-100 cursor-pointer"
              >
                Dismiss
              </button>
            </div>
          )}
        </div>

        {/* Right Side: Map Canvas */}
        <div className="lg:col-span-7 flex flex-col h-[580px] lg:h-auto min-h-[500px]">
          <RideGoMap
            pickup={pickup}
            drop={drop}
            drivers={drivers}
            routeCoordinates={routeResult?.coordinates}
            onMapClick={handleMapClick}
            theme={theme}
            className="w-full h-full"
          />
        </div>
      </main>
    </div>
  );
}

export default App;
