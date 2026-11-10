export interface RouteResult {
  coordinates: [number, number][]; // [lng, lat] format for MapLibre GeoJSON
  distanceKm: number;
  durationMinutes: number;
}

export class RoutingService {
  static async getRoute(
    startLat: number,
    startLng: number,
    endLat: number,
    endLng: number
  ): Promise<RouteResult | null> {
    try {
      // OSRM requires URL format: {startLng},{startLat};{endLng},{endLat}
      const url = `https://router.project-osrm.org/route/v1/driving/${startLng},${startLat};${endLng},${endLat}?overview=full&geometries=geojson`;

      const response = await fetch(url);
      if (!response.ok) return null;

      const data = await response.json();
      if (!data.routes || data.routes.length === 0) return null;

      const route = data.routes[0];
      const coordinates = route.geometry.coordinates as [number, number][];
      const distanceMeters = route.distance as number;
      const durationSeconds = route.duration as number;

      return {
        coordinates,
        distanceKm: Number((distanceMeters / 1000).toFixed(2)),
        durationMinutes: Math.round(durationSeconds / 60),
      };
    } catch (error) {
      console.error("OSRM Routing error:", error);
      return null;
    }
  }
}
