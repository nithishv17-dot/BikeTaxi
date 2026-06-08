import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../theme/premium_ui.dart';
import 'request_ride_screen.dart';
import 'ride_history_screen.dart';
import 'driver_list_screen.dart';
import 'driver_negotiation_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;

  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isLoading = true;
  String errorMessage = '';
  Map<String, dynamic> dashboardStats = {};

  @override
  void initState() {
    super.initState();
    fetchDashboard();
  }

  Future<void> fetchDashboard() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final response = await ApiService.getDashboard();

      if (!mounted) return;

      setState(() {
        dashboardStats = response;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    required Duration delay,
  }) {
    return Expanded(
      child: RevealMotion(
        delay: delay,
        child: ReflectionCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 18),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.slate900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: AppPalette.slate500,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Duration delay,
    required VoidCallback onTap,
  }) {
    return RevealMotion(
      delay: delay,
      child: ReflectionCard(
        onTap: onTap,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.slate900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppPalette.slate500,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppPalette.slate500,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return ReflectionCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Unable to load dashboard stats",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppPalette.slate900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              errorMessage,
              style: const TextStyle(
                color: AppPalette.slate500,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: fetchDashboard,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            _buildStatCard(
              "Total Rides",
              "${dashboardStats["totalRides"] ?? 0}",
              Icons.route_rounded,
              AppPalette.teal600,
              delay: const Duration(milliseconds: 220),
            ),
            const SizedBox(width: 14),
            _buildStatCard(
              "Completed",
              "${dashboardStats["completedRides"] ?? 0}",
              Icons.check_circle_rounded,
              const Color(0xFF16A34A),
              delay: const Duration(milliseconds: 280),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _buildStatCard(
              "Ongoing",
              "${dashboardStats["ongoingRides"] ?? 0}",
              Icons.directions_bike_rounded,
              AppPalette.sky500,
              delay: const Duration(milliseconds: 340),
            ),
            const SizedBox(width: 14),
            _buildStatCard(
              "Drivers Online",
              "${dashboardStats["availableDrivers"] ?? 0}",
              Icons.person_pin_circle_rounded,
              AppPalette.amber500,
              delay: const Duration(milliseconds: 400),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bike Taxi"),
        actions: [
          IconButton(
            onPressed: fetchDashboard,
            tooltip: "Refresh",
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: () {
              SessionService.clearSession();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            tooltip: "Logout",
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: fetchDashboard,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                const RevealMotion(
                  delay: Duration(milliseconds: 40),
                  beginOffset: Offset(0, -0.1),
                  child: ReflectiveBanner(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome back",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Book faster, track smarter,\nride better.",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.auto_graph_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Live performance insights",
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const RevealMotion(
                  delay: Duration(milliseconds: 160),
                  child: Text(
                    "Quick Stats",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.slate900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: _buildStatsSection(),
                ),
                const SizedBox(height: 28),
                const RevealMotion(
                  delay: Duration(milliseconds: 420),
                  child: Text(
                    "Actions",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.slate900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _buildActionCard(
                  title: "Request a Ride",
                  subtitle: "Book your next trip with live ride tracking.",
                  icon: Icons.local_taxi_rounded,
                  color: AppPalette.teal600,
                  delay: const Duration(milliseconds: 500),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            RequestRideScreen(userId: widget.userId),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _buildActionCard(
                  title: "Ride History",
                  subtitle:
                      "Review past rides, payments, and negotiation details.",
                  icon: Icons.history_rounded,
                  color: AppPalette.sky500,
                  delay: const Duration(milliseconds: 560),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            RideHistoryScreen(userId: widget.userId),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _buildActionCard(
                  title: "View Drivers",
                  subtitle:
                      "See available drivers and their live availability.",
                  icon: Icons.groups_rounded,
                  color: AppPalette.amber500,
                  delay: const Duration(milliseconds: 620),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DriverListScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _buildActionCard(
                  title: "Driver Negotiations",
                  subtitle:
                      "Test captain offers and base-fare acceptance flow.",
                  icon: Icons.sell_rounded,
                  color: const Color(0xFF7C3AED),
                  delay: const Duration(milliseconds: 680),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            DriverNegotiationScreen(driverId: widget.userId),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
