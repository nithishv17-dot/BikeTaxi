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
            final double lng = (coord[0] as num).toDouble();
            final double lat = (coord[1] as num).toDouble();
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
}
