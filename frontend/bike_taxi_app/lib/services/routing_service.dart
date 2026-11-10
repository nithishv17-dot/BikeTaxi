import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMinutes;

  RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

class RoutingService {
  static Future<RouteResult?> getRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    try {
      // OSRM HTTP request strictly formats coordinates in URL as {pickupLng},{pickupLat};{dropLng},{dropLat}
      final url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
        "$startLng,$startLat;$endLng,$endLat"
        "?overview=full&geometries=geojson",
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["routes"] != null && (data["routes"] as List).isNotEmpty) {
          final route = data["routes"][0];
          final geometry = route["geometry"] as Map<String, dynamic>;
          final coordinates = geometry["coordinates"] as List<dynamic>;

          // Decodes the GeoJSON coordinates and flips [Lng, Lat] to Flutter's [Lat, Lng] (LatLng) format
          final List<LatLng> points = coordinates.map((coord) {
            // OSRM returns [Longitude, Latitude]
            final double lng = (coord[0] as num).toDouble(); 
            final double lat = (coord[1] as num).toDouble(); 
            
            // latlong2 expects LatLng(Latitude, Longitude)
            return LatLng(lat, lng);
          }).toList();

          final double distanceMeters = (route["distance"] as num).toDouble();
          final double durationSeconds = (route["duration"] as num).toDouble();

          return RouteResult(
            points: points,
            distanceKm: distanceMeters / 1000.0,
            durationMinutes: durationSeconds / 60.0,
          );
        }
      }
    } catch (e) {
      print("OSRM Routing API error: $e");
    }
    return null;
  }

  /// Snaps a single GPS/pin coordinate to the nearest drivable road using OSRM nearest endpoint
  static Future<LatLng?> getNearestRoad(double lat, double lng) async {
    try {
      final url = Uri.parse(
        "https://router.project-osrm.org/nearest/v1/driving/$lng,$lat?number=1",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["waypoints"] != null && (data["waypoints"] as List).isNotEmpty) {
          final waypoint = data["waypoints"][0];
          final location = waypoint["location"] as List<dynamic>;
          final double snappedLng = (location[0] as num).toDouble();
          final double snappedLat = (location[1] as num).toDouble();
          return LatLng(snappedLat, snappedLng);
        }
      }
    } catch (_) {
      // Fallback returns null to preserve original pin
    }
    return null;
  }
}

