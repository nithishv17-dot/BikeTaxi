export interface GeoPosition {
  lat: number;
  lng: number;
}

export class LocationService {
  static getCurrentPosition(): Promise<GeoPosition | null> {
    return new Promise((resolve) => {
      if (!("geolocation" in navigator)) {
        console.warn("Geolocation not supported by this browser");
        resolve(null);
        return;
      }

      navigator.geolocation.getCurrentPosition(
        (position) => {
          resolve({
            lat: position.coords.latitude,
            lng: position.coords.longitude,
          });
        },
        (error) => {
          console.warn("Geolocation error:", error.message);
          resolve(null);
        },
        {
          enableHighAccuracy: true,
          timeout: 10000,
          maximumAge: 0,
        }
      );
    });
  }
}
