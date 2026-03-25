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
    static Future requestRide(
  String pickup,
  String destination,
) async {

  final response = await http.post(
    Uri.parse("$baseUrl/rides/request"),
    headers: {
      "Content-Type": "application/json"
    },
    body: jsonEncode({
      "pickup": pickup,
      "destination": destination
    }),
  );

  return jsonDecode(response.body);

}
}   