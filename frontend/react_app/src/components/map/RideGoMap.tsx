import { useEffect, useMemo, useRef } from "react";
import {
  Map,
  MapControls,
  MapMarker,
  MarkerContent,
  MarkerPopup,
  MapRoute,
  useMap,
} from "@/components/ui/map";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import {
  MapPin,
  Flag,
  Navigation,
  Bike,
  Phone,
  ShieldCheck,
} from "lucide-react";
import * as MapLibreGL from "maplibre-gl";

export interface MapPoint {
  lat: number;
  lng: number;
  address?: string;
  name?: string;
}

export interface MapDriver {
  driverId: string;
  name?: string;
  phone?: string;
  lat: number;
  lng: number;
  heading?: number;
  available?: boolean;
}

export interface RideGoMapProps {
  pickup?: MapPoint | null;
  drop?: MapPoint | null;
  drivers?: MapDriver[];
  routeCoordinates?: [number, number][]; // [lng, lat]
  onMapClick?: (coords: { lat: number; lng: number }) => void;
  className?: string;
  center?: [number, number]; // [lng, lat]
  zoom?: number;
  theme?: "light" | "dark";
  autoFit?: boolean;
}

/**
 * Handles map click events and camera framing inside the Map context
 */
function MapInteractions({
  pickup,
  drop,
  drivers = [],
  routeCoordinates,
  onMapClick,
  autoFit = true,
}: {
  pickup?: MapPoint | null;
  drop?: MapPoint | null;
  drivers?: MapDriver[];
  routeCoordinates?: [number, number][];
  onMapClick?: (coords: { lat: number; lng: number }) => void;
  autoFit?: boolean;
}) {
  const { map, isLoaded } = useMap();
  const lastFitBoundsRef = useRef<string>("");

  // Map Click Listener
  useEffect(() => {
    if (!map || !isLoaded || !onMapClick) return;

    const handleClick = (e: MapLibreGL.MapMouseEvent) => {
      onMapClick({
        lat: Number(e.lngLat.lat.toFixed(6)),
        lng: Number(e.lngLat.lng.toFixed(6)),
      });
    };

    map.on("click", handleClick);
    return () => {
      map.off("click", handleClick);
    };
  }, [map, isLoaded, onMapClick]);

  // Dynamic Camera Framing (fitBounds)
  useEffect(() => {
    if (!map || !isLoaded || !autoFit) return;

    const points: [number, number][] = [];

    if (pickup) {
      points.push([pickup.lng, pickup.lat]);
    }
    if (drop) {
      points.push([drop.lng, drop.lat]);
    }
    if (drivers && drivers.length > 0) {
      drivers.forEach((d) => points.push([d.lng, d.lat]));
    }
    if (routeCoordinates && routeCoordinates.length > 0) {
      // Sample route coordinates for framing
      for (let i = 0; i < routeCoordinates.length; i += Math.max(1, Math.floor(routeCoordinates.length / 10))) {
        points.push(routeCoordinates[i]);
      }
    }

    if (points.length === 0) return;

    if (points.length === 1) {
      map.easeTo({
        center: points[0],
        zoom: 15.5,
        duration: 1000,
      });
      return;
    }

    let minLng = points[0][0];
    let maxLng = points[0][0];
    let minLat = points[0][1];
    let maxLat = points[0][1];

    for (const [lng, lat] of points) {
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
    }

    const boundsKey = `${minLng.toFixed(4)},${minLat.toFixed(4)},${maxLng.toFixed(4)},${maxLat.toFixed(4)}`;
    if (boundsKey === lastFitBoundsRef.current) return;
    lastFitBoundsRef.current = boundsKey;

    try {
      const bounds = new MapLibreGL.LngLatBounds([minLng, minLat], [maxLng, maxLat]);
      map.fitBounds(bounds, {
        padding: { top: 80, bottom: 80, left: 80, right: 80 },
        maxZoom: 16.5,
        duration: 1200,
      });
    } catch (e) {
      console.warn("fitBounds error:", e);
    }
  }, [map, isLoaded, pickup, drop, drivers, routeCoordinates, autoFit]);

  return null;
}

export function RideGoMap({
  pickup,
  drop,
  drivers = [],
  routeCoordinates,
  onMapClick,
  className,
  center = [76.9558, 11.0168], // Default to Coimbatore, TN
  zoom = 13.5,
  theme,
  autoFit = true,
}: RideGoMapProps) {
  // Determine effective initial center
  const initialCenter = useMemo<[number, number]>(() => {
    if (pickup) return [pickup.lng, pickup.lat];
    if (drivers && drivers.length > 0) return [drivers[0].lng, drivers[0].lat];
    return center;
  }, [pickup, drivers, center]);

  // Road snapped points & walking connector logic
  const hasRoute = Boolean(routeCoordinates && routeCoordinates.length >= 2);
  const roadPickup = hasRoute
    ? { lng: routeCoordinates![0][0], lat: routeCoordinates![0][1] }
    : (pickup ? { lng: pickup.lng, lat: pickup.lat } : null);
  const roadDrop = hasRoute
    ? { lng: routeCoordinates![routeCoordinates!.length - 1][0], lat: routeCoordinates![routeCoordinates!.length - 1][1] }
    : (drop ? { lng: drop.lng, lat: drop.lat } : null);

  const getDistanceMeters = (p1: { lat: number; lng: number }, p2: { lat: number; lng: number }) => {
    const R = 6371e3;
    const φ1 = (p1.lat * Math.PI) / 180;
    const φ2 = (p2.lat * Math.PI) / 180;
    const Δφ = ((p2.lat - p1.lat) * Math.PI) / 180;
    const Δλ = ((p2.lng - p1.lng) * Math.PI) / 180;
    const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  };

  const isPickupOffRoad = Boolean(pickup && roadPickup && getDistanceMeters(pickup, roadPickup) > 5);
  const isDropOffRoad = Boolean(drop && roadDrop && getDistanceMeters(drop, roadDrop) > 5);

  return (
    <Card className={cn("p-0 overflow-hidden relative border-border/50 shadow-xl bg-card rounded-2xl", className)}>
      <Map
        center={initialCenter}
        zoom={zoom}
        theme={theme}
        className="w-full h-full min-h-[500px] relative"
      >
        <MapControls position="top-right" showZoom showLocate showCompass />

        {/* Camera framing and map interactions */}
        <MapInteractions
          pickup={pickup}
          drop={drop}
          drivers={drivers}
          routeCoordinates={routeCoordinates}
          onMapClick={onMapClick}
          autoFit={autoFit}
        />

        {/* Active Route Polyline */}
        {hasRoute && (
          <MapRoute
            id="ridego-active-route"
            coordinates={routeCoordinates!}
            color="#ff6b00"
            width={5.5}
            opacity={0.95}
          />
        )}

        {/* Pickup Walking Connector */}
        {isPickupOffRoad && pickup && roadPickup && (
          <MapRoute
            id="ridego-pickup-walking-route"
            coordinates={[
              [pickup.lng, pickup.lat],
              [roadPickup.lng, roadPickup.lat],
            ]}
            color="#ffffff"
            width={3}
            opacity={0.85}
            dashArray={[2, 2]}
          />
        )}

        {/* Drop-off Walking Connector */}
        {isDropOffRoad && drop && roadDrop && (
          <MapRoute
            id="ridego-drop-walking-route"
            coordinates={[
              [roadDrop.lng, roadDrop.lat],
              [drop.lng, drop.lat],
            ]}
            color="#ffffff"
            width={3}
            opacity={0.85}
            dashArray={[2, 2]}
          />
        )}

        {/* Pickup Off-Road Anchor Dot */}
        {isPickupOffRoad && pickup && (
          <MapMarker longitude={pickup.lng} latitude={pickup.lat}>
            <MarkerContent>
              <div className="w-3.5 h-3.5 rounded-full bg-emerald-500 border-2 border-white shadow-md" />
            </MarkerContent>
          </MapMarker>
        )}

        {/* Glowing Roadside Pickup Pin Marker */}
        {roadPickup && (
          <MapMarker longitude={roadPickup.lng} latitude={roadPickup.lat}>
            <MarkerContent>
              <div className="relative group cursor-pointer">
                <div className="absolute -inset-1.5 bg-emerald-500/40 rounded-full blur-xs animate-ping" />
                <div className="relative flex items-center justify-center w-10 h-10 bg-emerald-600 text-white rounded-full shadow-lg border-2 border-white ring-2 ring-emerald-500/50 hover:scale-110 transition-transform">
                  <MapPin className="w-5 h-5 fill-white" />
                </div>
              </div>
            </MarkerContent>
            <MarkerPopup className="bg-popover text-popover-foreground p-3 rounded-xl shadow-xl border border-border/50 min-w-[200px]">
              <div className="flex items-center gap-2 mb-1.5">
                <div className="w-2.5 h-2.5 rounded-full bg-emerald-500 animate-pulse" />
                <span className="text-xs font-bold uppercase tracking-wider text-emerald-600 dark:text-emerald-400">
                  Pickup Location
                </span>
              </div>
              <p className="text-sm font-semibold text-foreground line-clamp-2">
                {pickup?.address || pickup?.name || "Selected Pickup"}
              </p>
              <p className="text-[11px] text-muted-foreground mt-1 font-mono">
                {roadPickup.lat.toFixed(5)}, {roadPickup.lng.toFixed(5)}
              </p>
            </MarkerPopup>
          </MapMarker>
        )}

        {/* Drop-off Off-Road Anchor Dot */}
        {isDropOffRoad && drop && (
          <MapMarker longitude={drop.lng} latitude={drop.lat}>
            <MarkerContent>
              <div className="w-3.5 h-3.5 rounded-full bg-rose-500 border-2 border-white shadow-md" />
            </MarkerContent>
          </MapMarker>
        )}

        {/* Glowing Roadside Drop-off Pin Marker */}
        {roadDrop && (
          <MapMarker longitude={roadDrop.lng} latitude={roadDrop.lat}>
            <MarkerContent>
              <div className="relative group cursor-pointer">
                <div className="absolute -inset-1.5 bg-rose-500/40 rounded-full blur-xs animate-pulse" />
                <div className="relative flex items-center justify-center w-10 h-10 bg-rose-600 text-white rounded-full shadow-lg border-2 border-white ring-2 ring-rose-500/50 hover:scale-110 transition-transform">
                  <Flag className="w-5 h-5 fill-white" />
                </div>
              </div>
            </MarkerContent>
            <MarkerPopup className="bg-popover text-popover-foreground p-3 rounded-xl shadow-xl border border-border/50 min-w-[200px]">
              <div className="flex items-center gap-2 mb-1.5">
                <div className="w-2.5 h-2.5 rounded-full bg-rose-500" />
                <span className="text-xs font-bold uppercase tracking-wider text-rose-600 dark:text-rose-400">
                  Drop-off Destination
                </span>
              </div>
              <p className="text-sm font-semibold text-foreground line-clamp-2">
                {drop?.address || drop?.name || "Selected Drop-off"}
              </p>
              <p className="text-[11px] text-muted-foreground mt-1 font-mono">
                {roadDrop.lat.toFixed(5)}, {roadDrop.lng.toFixed(5)}
              </p>
            </MarkerPopup>
          </MapMarker>
        )}

        {/* Live Bike Driver Pins */}
        {drivers.map((driver) => (
          <MapMarker
            key={driver.driverId}
            longitude={driver.lng}
            latitude={driver.lat}
          >
            <MarkerContent>
              <div className="relative group cursor-pointer">
                <div className="absolute -inset-1 bg-amber-500/30 rounded-full blur-[2px] animate-pulse" />
                <div
                  className="relative flex items-center justify-center w-9 h-9 bg-slate-900 dark:bg-amber-500 text-amber-400 dark:text-slate-950 rounded-full shadow-lg border border-amber-400/80 hover:scale-115 transition-transform"
                  style={{
                    transform: driver.heading ? `rotate(${driver.heading}deg)` : undefined,
                  }}
                >
                  <Bike className="w-5 h-5" />
                </div>
              </div>
            </MarkerContent>
            <MarkerPopup className="bg-popover text-popover-foreground p-3 rounded-xl shadow-xl border border-border/50 min-w-[190px]">
              <div className="flex items-center justify-between gap-2 mb-1">
                <div className="flex items-center gap-1.5">
                  <Bike className="w-4 h-4 text-amber-500" />
                  <span className="text-sm font-bold text-foreground">
                    {driver.name || "Bike Taxi Driver"}
                  </span>
                </div>
                <span className="px-1.5 py-0.5 text-[10px] font-semibold rounded bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
                  Online
                </span>
              </div>
              {driver.phone && (
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground mt-1">
                  <Phone className="w-3.5 h-3.5" />
                  <span>{driver.phone}</span>
                </div>
              )}
              <div className="flex items-center gap-1 text-[11px] text-muted-foreground mt-1">
                <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
                <span>RideGo Verified Captain</span>
              </div>
            </MarkerPopup>
          </MapMarker>
        ))}
      </Map>

      {/* Floating Map Overlay Badge */}
      <div className="absolute bottom-4 left-4 z-10 pointer-events-none flex items-center gap-2 bg-background/85 dark:bg-slate-900/85 backdrop-blur-md px-3 py-1.5 rounded-full border border-border/60 shadow-md">
        <Navigation className="w-3.5 h-3.5 text-amber-500 animate-spin [animation-duration:8s]" />
        <span className="text-xs font-semibold text-foreground tracking-tight">
          RideGo Live GIS Engine
        </span>
        <span className="text-[10px] text-muted-foreground">• MapLibre + OSRM</span>
      </div>
    </Card>
  );
}
