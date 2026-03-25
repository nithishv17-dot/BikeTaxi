import 'dart:convert';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
class ApiService {
  static const String baseUrl = "http://localhost:5000/api";

  static Future<Map<String, dynamic>> login(
    String phone,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "phone": phone,
        "password": password,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> toggleDriver(String driverId) async {
  final response = await http.post(
    Uri.parse("$baseUrl/drivers/toggle/$driverId"),
    headers: {"Content-Type": "application/json"},
  );

  return _handleResponse(response);
}
static Future<Map<String, dynamic>> getDrivers() async {
  final uri = Uri.parse("$baseUrl/users/drivers-list");
  print("CALLING: $uri");

  final response = await http.post(
    uri,
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({}),
  );

  return _handleResponse(response);
}
  static Future<Map<String, dynamic>> register(
    String name,
    String phone,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "name": name,
        "phone": phone,
        "password": password,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> requestRide(
    String userId,
    String pickup,
    String destination,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/request"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "pickup": pickup,
        "destination": destination,
      }),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getRide(String rideId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/$rideId"),
      
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> startRide(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/start/$rideId"),
      headers: {"Content-Type": "application/json"},
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> completeRide(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/complete/$rideId"),
      headers: {"Content-Type": "application/json"},
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> cancelRide(String rideId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rides/cancel/$rideId"),
      headers: {"Content-Type": "application/json"},
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getUserRideHistory(String userId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/rides/user/$userId/history"),
      
    );

    return _handleResponse(response);
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    print("STATUS CODE: ${response.statusCode}");
    print("RAW RESPONSE BODY: ${response.body}");

    dynamic data;

    try {
      data = jsonDecode(response.body);
    } catch (e) {
      throw Exception(
        "Invalid JSON response | Status: ${response.statusCode} | Body: ${response.body}",
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(
        data["message"] ?? "Server error | Status: ${response.statusCode}",
      );
    }
  }
}