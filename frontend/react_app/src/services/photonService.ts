export interface PhotonPlace {
  placeId: string;
  name: string;
  address: string;
  lat: number;
  lng: number;
}

export class PhotonService {
  private static baseUrl = "https://photon.komoot.io";

  static formatPlaceLabel(properties: Record<string, any>): string {
    const parts: string[] = [];
    if (properties.name) parts.push(properties.name);
    if (properties.street) parts.push(properties.street);
    if (properties.district && properties.district !== properties.name) parts.push(properties.district);
    if (properties.city && properties.city !== properties.name) parts.push(properties.city);
    if (properties.state) parts.push(properties.state);

    return parts.length > 0 ? parts.join(", ") : "Selected Location";
  }

  static async searchPlaces(
    query: string,
    biasLat?: number,
    biasLng?: number
  ): Promise<PhotonPlace[]> {
    if (!query.trim()) return [];

    try {
      const lat = biasLat ?? 11.0168;
      const lon = biasLng ?? 76.9558;
      const url = `${this.baseUrl}/api/?q=${encodeURIComponent(query.trim())}&limit=8&lat=${lat}&lon=${lon}`;

      const response = await fetch(url);
      if (!response.ok) return [];

      const data = await response.json();
      if (!data.features) return [];

      return data.features.map((feature: any, index: number) => {
        const [lng, lat] = feature.geometry.coordinates;
        const address = this.formatPlaceLabel(feature.properties);
        return {
          placeId: feature.properties.osm_id?.toString() || `photon_${index}_${Date.now()}`,
          name: feature.properties.name || address,
          address,
          lat,
          lng,
        };
      });
    } catch (error) {
      console.error("Photon search error:", error);
      return [];
    }
  }

  static async reverseGeocode(lat: number, lng: number): Promise<PhotonPlace | null> {
    try {
      const url = `${this.baseUrl}/reverse?lat=${lat}&lon=${lng}&limit=1`;
      const response = await fetch(url);
      if (!response.ok) return null;

      const data = await response.json();
      if (!data.features || data.features.length === 0) return null;

      const feature = data.features[0];
      const address = this.formatPlaceLabel(feature.properties);

      return {
        placeId: feature.properties.osm_id?.toString() || `reverse_${lat}_${lng}`,
        name: feature.properties.name || address,
        address,
        lat,
        lng,
      };
    } catch (error) {
      console.error("Photon reverse geocode error:", error);
      return null;
    }
  }
}
