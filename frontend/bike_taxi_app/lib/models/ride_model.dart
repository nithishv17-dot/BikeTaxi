import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class RideModel {
  final String pickup;
  final String destination;

  RideModel({
    required this.pickup,
    required this.destination,
  });

  Map<String, dynamic> toJson() {
    return {
      "pickup": pickup,
      "destination": destination,
    };
  }

  static Future<Map<String, dynamic>> requestRide(
    String pickup,
    String destination,
  ) async {
    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/rides/request"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "pickup": pickup,
        "destination": destination,
      }),
    );

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
