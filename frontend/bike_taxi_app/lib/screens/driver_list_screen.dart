import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'driver_list_screen.dart';
class DriverListScreen extends StatefulWidget {
  const DriverListScreen({super.key});

  @override
  State<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends State<DriverListScreen> {
  List<dynamic> drivers = [];
  bool isLoading = true;
  String message = "";

  @override
  void initState() {
    super.initState();
    fetchDrivers();
  }

  Future<void> fetchDrivers() async {
  setState(() {
    isLoading = true;
    message = "";
  });

  try {
    final response = await ApiService.getDrivers();
    print("DRIVERS RESPONSE: $response");

    setState(() {
      drivers = response["drivers"] ?? [];
      isLoading = false;
    });
  } catch (e) {
    print("DRIVERS ERROR: $e");

    setState(() {
      message = e.toString().replaceFirst("Exception: ", "");
      isLoading = false;
    });
  }
}

  Widget buildDriverCard(Map<String, dynamic> driver) {
    final name = driver["name"]?.toString() ?? "";
    final phone = driver["phone"]?.toString() ?? "";
    final isAvailable = driver["isAvailable"] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(name),
        subtitle: Text(phone),
        trailing: Text(
          isAvailable ? "ONLINE" : "OFFLINE",
          style: TextStyle(
            color: isAvailable ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Drivers"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : drivers.isEmpty
                ? Center(
                    child: Text(message.isEmpty ? "No drivers found" : message),
                  )
                : RefreshIndicator(
                    onRefresh: fetchDrivers,
                    child: ListView(
                      children: drivers
                          .map((driver) => buildDriverCard(driver))
                          .toList(),
                    ),
                  ),
      ),
    );
  }
}