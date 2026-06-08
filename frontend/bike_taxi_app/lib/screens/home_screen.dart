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
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "RideGo" : "My Profile"),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          RequestRideScreen(userId: widget.userId, isEmbedded: true),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: Colors.white.withOpacity(0.94),
            indicatorColor: AppPalette.primary.withOpacity(0.12),
            height: 70,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.directions_bike_rounded, color: AppPalette.slate500),
                selectedIcon: Icon(Icons.directions_bike_rounded, color: AppPalette.primary),
                label: "Home",
              ),
              NavigationDestination(
                icon: Icon(Icons.person_rounded, color: AppPalette.slate500),
                selectedIcon: Icon(Icons.person_rounded, color: AppPalette.primary),
                label: "Profile",
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getUserProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Error loading profile: ${snapshot.error}",
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          );
        }

        final profile = snapshot.data ?? {};
        final name = profile["name"] ?? "Rider";
        final phone = profile["phone"] ?? "";
        final role = profile["role"] ?? "Rider";
        final initials = name.split(" ").map((s) => s.isNotEmpty ? s[0] : "").join().toUpperCase();

        return PremiumBackdrop(
          accentColor: AppPalette.primary,
          secondaryColor: AppPalette.secondary,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              children: [
                RevealMotion(
                  delay: const Duration(milliseconds: 60),
                  child: ReflectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 54,
                          backgroundColor: AppPalette.primary,
                          child: Text(
                            initials.isNotEmpty ? initials : "R",
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.slate900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "+91 $phone",
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.slate500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            role.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.primary,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Account & Actions",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.slate900,
                  ),
                ),
                const SizedBox(height: 12),
                RevealMotion(
                  delay: const Duration(milliseconds: 140),
                  child: ReflectionCard(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RideHistoryScreen(userId: widget.userId),
                        ),
                      );
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.history_rounded, color: AppPalette.primary),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Ride History",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.slate900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "View all your past trips and receipts",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppPalette.slate500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppPalette.slate500),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                RevealMotion(
                  delay: const Duration(milliseconds: 200),
                  child: ReflectionCard(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DriverListScreen(),
                        ),
                      );
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.directions_bike_rounded, color: Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "View Captains",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.slate900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Check all online captains nearby",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppPalette.slate500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppPalette.slate500),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                RevealMotion(
                  delay: const Duration(milliseconds: 260),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      SessionService.clearSession();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text(
                      "Log Out",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
