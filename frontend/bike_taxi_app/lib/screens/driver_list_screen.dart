import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/premium_ui.dart';

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

  Widget _buildStatusBadge(bool isAvailable) {
    final color = isAvailable
        ? AppPalette.secondary
        : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAvailable ? "ONLINE" : "OFFLINE",
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget buildDriverCard(Map<String, dynamic> driver) {
    final name = driver["name"]?.toString() ?? "";
    final phone = driver["phone"]?.toString() ?? "";
    final isAvailable = driver["isAvailable"] ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ReflectionCard(
        padding: const EdgeInsets.all(18),
        borderRadius: BorderRadius.circular(22),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: isAvailable
                  ? AppPalette.secondary.withOpacity(0.12)
                  : const Color(0xFFFEE2E2),
              child: Icon(
                Icons.person_rounded,
                color: isAvailable
                    ? AppPalette.secondary
                    : const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.slate900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: const TextStyle(
                      color: AppPalette.slate500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _buildStatusBadge(isAvailable),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Drivers"),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: fetchDrivers,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        accentColor: AppPalette.primary,
        secondaryColor: AppPalette.secondary,
        child: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: fetchDrivers,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      const RevealMotion(
                        delay: Duration(milliseconds: 40),
                        beginOffset: Offset(0, -0.1),
                        child: ReflectiveBanner(
                          colors: const [AppPalette.primary, AppPalette.secondary],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Live Fleet",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Monitor captain\navailability in real time.",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (drivers.isEmpty)
                        ReflectionCard(
                          borderRadius: BorderRadius.circular(20),
                          child: Text(
                            message.isEmpty ? "No drivers found" : message,
                            style: const TextStyle(
                              color: AppPalette.slate600,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        ...drivers.map((driver) => buildDriverCard(driver)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
