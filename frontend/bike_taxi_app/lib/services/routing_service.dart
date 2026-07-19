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
  static List<LatLng> decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  static Future<RouteResult?> getRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    try {
      final url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
        "$startLng,$startLat;$endLng,$endLat"
        "?overview=full&geometries=polyline",
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["routes"] != null && (data["routes"] as List).isNotEmpty) {
          final route = data["routes"][0];
          final geometry = route["geometry"] as String;
          final points = decodePolyline(geometry);

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
