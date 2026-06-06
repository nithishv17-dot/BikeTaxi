import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../theme/premium_ui.dart';
import 'ride_status_screen.dart';

class RequestRideScreen extends StatefulWidget {
  final String userId;

  const RequestRideScreen({super.key, required this.userId});

  @override
  State<RequestRideScreen> createState() => _RequestRideScreenState();
}

class _RequestRideScreenState extends State<RequestRideScreen> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  Timer? pickupDebounce;
  Timer? dropDebounce;

  List<Map<String, dynamic>> pickupSuggestions = [];
  List<Map<String, dynamic>> dropSuggestions = [];

  String selectedPaymentMethod = "Cash";
  String bookingMode = "normal";
  String pickupInput = "";
  String dropInput = "";
  String? pickupAddress;
  String? pickupPlaceId;
  double? pickupLat;
  double? pickupLng;
  String? dropAddress;
  String? dropPlaceId;
  double? dropLat;
  double? dropLng;
  bool isSearchingPickup = false;
  bool isSearchingDrop = false;
  bool pickupNoResults = false;
  bool dropNoResults = false;
  String? pickupError;
  String? dropError;
  String message = "";
  bool isLoading = false;

  bool get canSubmit {
    return !isLoading &&
        !isSearchingPickup &&
        !isSearchingDrop &&
        !_hasSamePickupAndDrop &&
        _isValidSelectedLocation(
          input: pickupController.text,
          address: pickupAddress,
          lat: pickupLat,
          lng: pickupLng,
        ) &&
        _isValidSelectedLocation(
          input: destinationController.text,
          address: dropAddress,
          lat: dropLat,
          lng: dropLng,
        );
  }

  double? get estimatedFare {
    if (pickupLat == null ||
        pickupLng == null ||
        dropLat == null ||
        dropLng == null) {
      return null;
    }

    const double earthRadiusKm = 6371;
    final double dLat = (dropLat! - pickupLat!) * 3.141592653589793 / 180;
    final double dLng = (dropLng! - pickupLng!) * 3.141592653589793 / 180;
    final double lat1 = pickupLat! * 3.141592653589793 / 180;
    final double lat2 = dropLat! * 3.141592653589793 / 180;
    final double a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final double distanceKm = earthRadiusKm * c;
    return (40 + (distanceKm * 12)).clamp(40, 100000).toDouble();
  }

  void _clearPickupSelection() {
    pickupAddress = null;
    pickupPlaceId = null;
    pickupLat = null;
    pickupLng = null;
    pickupError = pickupInput.trim().isEmpty
        ? null
        : "Search and select a pickup result";
  }

  void _clearDropSelection() {
    dropAddress = null;
    dropPlaceId = null;
    dropLat = null;
    dropLng = null;
    dropError = dropInput.trim().isEmpty
        ? null
        : "Search and select a drop result";
  }

  bool _isValidLatitude(double value) {
    return value >= -90 && value <= 90;
  }

  bool _isValidLongitude(double value) {
    return value >= -180 && value <= 180;
  }

  bool _isValidSelectedLocation({
    required String input,
    required String? address,
    required double? lat,
    required double? lng,
  }) {
    return address != null &&
        lat != null &&
        lng != null &&
        input.trim() == address &&
        _isValidLatitude(lat) &&
        _isValidLongitude(lng);
  }

  bool get _hasSamePickupAndDrop {
    if (pickupAddress == null ||
        dropAddress == null ||
        pickupLat == null ||
        pickupLng == null ||
        dropLat == null ||
        dropLng == null) {
      return false;
    }

    return pickupAddress == dropAddress ||
        (pickupLat == dropLat && pickupLng == dropLng);
  }

  void _onPickupChanged(String value) {
    pickupInput = value;

    setState(() {
      message = "";
      pickupNoResults = false;
      if (value.trim() != pickupAddress) {
        _clearPickupSelection();
        pickupSuggestions = [];
      } else {
        pickupError = null;
      }
    });

    pickupDebounce?.cancel();

    if (value.trim().length < 3) {
      setState(() {
        isSearchingPickup = false;
        pickupSuggestions = [];
        pickupNoResults = false;
      });
      return;
    }

    pickupDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(isPickup: true);
    });
  }

  void _onDropChanged(String value) {
    dropInput = value;

    setState(() {
      message = "";
      dropNoResults = false;
      if (value.trim() != dropAddress) {
        _clearDropSelection();
        dropSuggestions = [];
      } else {
        dropError = null;
      }
    });

    dropDebounce?.cancel();

    if (value.trim().length < 3) {
      setState(() {
        isSearchingDrop = false;
        dropSuggestions = [];
        dropNoResults = false;
      });
      return;
    }

    dropDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(isPickup: false);
    });
  }

  Future<void> _searchPlaces({required bool isPickup}) async {
    final query = isPickup
        ? pickupController.text.trim()
        : destinationController.text.trim();

    if (query.length < 3) {
      setState(() {
        if (isPickup) {
          pickupError = "Enter at least 3 characters to search";
          pickupSuggestions = [];
          pickupNoResults = false;
        } else {
          dropError = "Enter at least 3 characters to search";
          dropSuggestions = [];
          dropNoResults = false;
        }
      });
      return;
    }

    setState(() {
      message = "";
      if (isPickup) {
        isSearchingPickup = true;
        pickupError = null;
        pickupNoResults = false;
      } else {
        isSearchingDrop = true;
        dropError = null;
        dropNoResults = false;
      }
    });

    try {
      final results = await ApiService.searchPhotonPlaces(query);

      if (!mounted) return;

      setState(() {
        if (isPickup) {
          isSearchingPickup = false;
          pickupSuggestions = results;
          pickupNoResults = results.isEmpty;
        } else {
          isSearchingDrop = false;
          dropSuggestions = results;
          dropNoResults = results.isEmpty;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        if (isPickup) {
          isSearchingPickup = false;
          pickupSuggestions = [];
        } else {
          isSearchingDrop = false;
          dropSuggestions = [];
        }
        message = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  void _selectSuggestion(
    Map<String, dynamic> suggestion, {
    required bool isPickup,
  }) {
    final placeId = suggestion["placeId"]?.toString() ?? "";
    final address = suggestion["address"]?.toString() ?? "";
    final lat = suggestion["lat"] is num
        ? (suggestion["lat"] as num).toDouble()
        : double.tryParse("${suggestion["lat"]}");
    final lng = suggestion["lng"] is num
        ? (suggestion["lng"] as num).toDouble()
        : double.tryParse("${suggestion["lng"]}");

    if (placeId.isEmpty || address.isEmpty || lat == null || lng == null) {
      setState(() {
        message = "Unable to use the selected place";
      });
      return;
    }

    setState(() {
      message = "";
      if (isPickup) {
        pickupController.text = address;
        pickupInput = address;
        pickupAddress = address;
        pickupPlaceId = placeId;
        pickupLat = lat;
        pickupLng = lng;
        pickupError = null;
        pickupSuggestions = [];
        pickupNoResults = false;
      } else {
        destinationController.text = address;
        dropInput = address;
        dropAddress = address;
        dropPlaceId = placeId;
        dropLat = lat;
        dropLng = lng;
        dropError = null;
        dropSuggestions = [];
        dropNoResults = false;
      }

      if (_hasSamePickupAndDrop) {
        pickupError = "Pickup location must be different from drop";
        dropError = "Drop location must be different from pickup";
      }
    });
  }

  Widget _buildLocationSearchField({
    required String label,
    required String hintText,
    required String helperText,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required bool isSearching,
    required String? errorText,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        errorText: errorText,
        prefixIcon: Icon(icon),
        suffixIcon: isSearching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildSuggestionsList(
    List<Map<String, dynamic>> suggestions, {
    required bool isPickup,
  }) {
    final isSearching = isPickup ? isSearchingPickup : isSearchingDrop;
    final showNoResults = isPickup ? pickupNoResults : dropNoResults;

    if (suggestions.isEmpty && !isSearching && !showNoResults) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ReflectionCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                isPickup ? "Pickup results" : "Drop results",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            if (isSearching)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Searching places...",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (!isSearching && suggestions.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  final subtitle = suggestion["subtitle"]?.toString() ?? "";

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isPickup
                          ? Icons.my_location_rounded
                          : Icons.flag_circle_rounded,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: Text(
                      suggestion["address"]?.toString() ?? "",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: subtitle.isEmpty
                        ? const Text("Tap to use this result")
                        : Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () =>
                        _selectSuggestion(suggestion, isPickup: isPickup),
                  );
                },
              ),
            if (!isSearching && suggestions.isEmpty && showNoResults)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.search_off_rounded, color: Color(0xFF64748B)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "No matching places found. Try a more specific address and search again.",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionSummary({
    required String title,
    required String? address,
    required double? lat,
    required double? lng,
    required Color accent,
  }) {
    if (address == null || lat == null || lng == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  "Lat ${lat.toStringAsFixed(6)} | Lng ${lng.toStringAsFixed(6)}",
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewMap() {
    final previewPoints = <LatLng>[
      if (pickupLat != null && pickupLng != null)
        LatLng(pickupLat!, pickupLng!),
      if (dropLat != null && dropLng != null) LatLng(dropLat!, dropLng!),
    ];

    if (previewPoints.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.58),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBFDBFE).withOpacity(0.65)),
        ),
        child: const Row(
          children: [
            Icon(Icons.map_outlined, color: Color(0xFF64748B)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                "Search and select pickup and drop locations to preview them on the map.",
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final linePoints = previewPoints.length == 2
        ? [previewPoints.first, previewPoints.last]
        : <LatLng>[];

    final center = previewPoints.length == 2
        ? LatLng(
            (previewPoints[0].latitude + previewPoints[1].latitude) / 2,
            (previewPoints[0].longitude + previewPoints[1].longitude) / 2,
          )
        : previewPoints.first;

    final markers = <Marker>[
      if (pickupLat != null && pickupLng != null)
        Marker(
          point: LatLng(pickupLat!, pickupLng!),
          width: 44,
          height: 44,
          child: const Icon(
            Icons.my_location_rounded,
            size: 34,
            color: Color(0xFF16A34A),
          ),
        ),
      if (dropLat != null && dropLng != null)
        Marker(
          point: LatLng(dropLat!, dropLng!),
          width: 44,
          height: 44,
          child: const Icon(
            Icons.flag_rounded,
            size: 34,
            color: Color(0xFFDC2626),
          ),
        ),
    ];

    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: previewPoints.length == 2 ? 11.5 : 14,
                onTap: (tapPosition, point) => _onMapTapped(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: "com.example.bike_taxi_app",
                ),
                if (linePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: linePoints,
                        color: AppPalette.primary.withOpacity(0.9),
                        strokeWidth: 4.4,
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.84),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.alt_route_rounded,
                      size: 15,
                      color: AppPalette.slate600,
                    ),
                    SizedBox(width: 6),
                    Text(
                      "Live route preview",
                      style: TextStyle(
                        color: AppPalette.slate600,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMapTapped(LatLng point) {
    if (pickupLat == null || pickupLng == null) {
      setState(() {
        pickupLat = point.latitude;
        pickupLng = point.longitude;
        pickupAddress = "Map Tap (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})";
        pickupController.text = pickupAddress!;
        pickupPlaceId = "map_tap_pickup";
        pickupError = null;
        message = "Pickup set from map tap";
      });
    } else {
      setState(() {
        dropLat = point.latitude;
        dropLng = point.longitude;
        dropAddress = "Map Tap (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})";
        destinationController.text = dropAddress!;
        dropPlaceId = "map_tap_drop";
        dropError = null;
        message = "Drop set from map tap";
      });
    }
  }

  void _showFareBreakdown() {
    final double? fare = estimatedFare;
    if (fare == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ReflectionCard(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Fare Breakdown",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.slate900,
                ),
              ),
              const SizedBox(height: 16),
              _buildFareDetailRow("Base Fare", "Rs. 40.00"),
              const SizedBox(height: 10),
              _buildFareDetailRow("Distance Charge", "Rs. ${((fare - 40).clamp(0, 100000)).toStringAsFixed(2)}"),
              const Divider(height: 24),
              _buildFareDetailRow("Total Estimated Fare", "Rs. ${fare.toStringAsFixed(2)}", isTotal: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Got it"),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFareDetailRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            fontSize: isTotal ? 16 : 14,
            color: isTotal ? AppPalette.slate900 : AppPalette.slate600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w800,
            fontSize: isTotal ? 18 : 14,
            color: isTotal ? AppPalette.primary : AppPalette.slate900,
          ),
        ),
      ],
    );
  }

  void requestRide() async {
    if (!canSubmit) {
      setState(() {
        pickupError =
            _isValidSelectedLocation(
              input: pickupController.text,
              address: pickupAddress,
              lat: pickupLat,
              lng: pickupLng,
            )
            ? null
            : "Search and select a valid pickup location";
        dropError =
            _isValidSelectedLocation(
              input: destinationController.text,
              address: dropAddress,
              lat: dropLat,
              lng: dropLng,
            )
            ? null
            : "Search and select a valid drop location";
        if (_hasSamePickupAndDrop) {
          pickupError = "Pickup location must be different from drop";
          dropError = "Drop location must be different from pickup";
        }
        message =
            "Pick a valid pickup and drop result before requesting the ride";
      });
      return;
    }

    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.requestRide(
        widget.userId,
        pickupAddress!,
        pickupLat!,
        pickupLng!,
        dropAddress!,
        dropLat!,
        dropLng!,
        selectedPaymentMethod,
        pickupPlaceId,
        dropPlaceId,
        bookingMode,
        estimatedFare ?? 0,
      );

      if (!mounted) return;

      setState(() {
        message = response["message"] ?? "Ride requested successfully";
      });

      if (response["ride"] != null && response["ride"]["_id"] != null) {
        final String rideId = response["ride"]["_id"];

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RideStatusScreen(rideId: rideId),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    pickupDebounce?.cancel();
    dropDebounce?.cancel();
    pickupController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Request Ride")),
      body: PremiumBackdrop(
        accentColor: AppPalette.primary,
        secondaryColor: AppPalette.secondary,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const RevealMotion(
                delay: Duration(milliseconds: 40),
                beginOffset: Offset(0, -0.1),
                child: ReflectiveBanner(
                  colors: [AppPalette.primary, Color(0xFF4F46E5)],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Route Commander",
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Craft your ride with\nlive map intelligence.",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 29,
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
              RevealMotion(
                delay: const Duration(milliseconds: 140),
                child: ReflectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Plan Your Ride",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.slate900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Type addresses and pick one live Photon result for each stop.",
                        style: TextStyle(
                          color: AppPalette.slate500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                       _buildLocationSearchField(
                        label: "Pickup Location",
                        hintText: "Start typing pickup address",
                        helperText:
                            "Suggestions appear automatically after 3 characters.",
                        controller: pickupController,
                        onChanged: _onPickupChanged,
                        isSearching: isSearchingPickup,
                        errorText: pickupError,
                        icon: Icons.my_location_rounded,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text("Quick: ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.slate500)),
                            const SizedBox(width: 4),
                            ...[
                              {
                                "name": "Current Location",
                                "address": "MG Road Metro Station, Bangalore",
                                "lat": 12.9756,
                                "lng": 77.6067,
                                "placeId": "current_loc_preset"
                              },
                              {
                                "name": "Tech Park Gate 1",
                                "address": "Manyata Tech Park Gate 1, Bangalore",
                                "lat": 13.0451,
                                "lng": 77.6266,
                                "placeId": "techpark_gate1_preset"
                              }
                            ].map((preset) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                avatar: const Icon(Icons.my_location_rounded, size: 12, color: AppPalette.primary),
                                label: Text(preset["name"] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  _selectSuggestion({
                                    "placeId": preset["placeId"],
                                    "address": preset["address"],
                                    "lat": preset["lat"],
                                    "lng": preset["lng"],
                                  }, isPickup: true);
                                },
                              ),
                            )),
                          ],
                        ),
                      ),
                      _buildSuggestionsList(pickupSuggestions, isPickup: true),
                      _buildSelectionSummary(
                        title: "Pickup selected",
                        address: pickupAddress,
                        lat: pickupLat,
                        lng: pickupLng,
                        accent: const Color(0xFF16A34A),
                      ),
                      const SizedBox(height: 15),
                       _buildLocationSearchField(
                        label: "Drop Location",
                        hintText: "Start typing destination address",
                        helperText:
                            "Suggestions appear automatically after 3 characters.",
                        controller: destinationController,
                        onChanged: _onDropChanged,
                        isSearching: isSearchingDrop,
                        errorText: dropError,
                        icon: Icons.flag_rounded,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text("Quick: ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.slate500)),
                            const SizedBox(width: 4),
                            ...[
                              {
                                "name": "Home",
                                "address": "123 Green Glen Layout, Outer Ring Road, Bangalore",
                                "lat": 12.9279,
                                "lng": 77.6271,
                                "placeId": "home_preset"
                              },
                              {
                                "name": "Office",
                                "address": "Embassy TechVillage, Bellandur, Bangalore",
                                "lat": 12.9784,
                                "lng": 77.6408,
                                "placeId": "office_preset"
                              },
                              {
                                "name": "Metro Station",
                                "address": "Indiranagar Metro Station, Bangalore",
                                "lat": 12.9716,
                                "lng": 77.5946,
                                "placeId": "metro_preset"
                              },
                              {
                                "name": "Airport",
                                "address": "Kempegowda International Airport, Bangalore",
                                "lat": 13.1986,
                                "lng": 77.7066,
                                "placeId": "airport_preset"
                              }
                            ].map((preset) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                avatar: const Icon(Icons.place_rounded, size: 12, color: AppPalette.accent),
                                label: Text(preset["name"] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  _selectSuggestion({
                                    "placeId": preset["placeId"],
                                    "address": preset["address"],
                                    "lat": preset["lat"],
                                    "lng": preset["lng"],
                                  }, isPickup: false);
                                },
                              ),
                            )),
                          ],
                        ),
                      ),
                      _buildSuggestionsList(dropSuggestions, isPickup: false),
                      _buildSelectionSummary(
                        title: "Drop selected",
                        address: dropAddress,
                        lat: dropLat,
                        lng: dropLng,
                        accent: const Color(0xFFDC2626),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Booking Mode",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.slate900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        style: ButtonStyle(
                          textStyle: WidgetStateProperty.all(
                            const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          side: WidgetStateProperty.all(
                            BorderSide(
                              color: AppPalette.primary.withOpacity(0.26),
                            ),
                          ),
                        ),
                        segments: const [
                          ButtonSegment<String>(
                            value: "normal",
                            label: Text("Normal"),
                            icon: Icon(Icons.local_taxi_rounded),
                          ),
                          ButtonSegment<String>(
                            value: "negotiation",
                            label: Text("Negotiation"),
                            icon: Icon(Icons.sell_rounded),
                          ),
                        ],
                        selected: {bookingMode},
                        onSelectionChanged: (selection) {
                          setState(() {
                            bookingMode = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: estimatedFare == null ? null : _showFareBreakdown,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFDBEAFE).withOpacity(0.55),
                                Colors.white.withOpacity(0.72),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFBFDBFE).withOpacity(0.7),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.payments_outlined,
                                color: AppPalette.slate600,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "Estimated Fare",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: AppPalette.slate900,
                                          ),
                                        ),
                                        if (estimatedFare != null)
                                          const Text(
                                            "Tap for breakdown",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppPalette.primary,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      estimatedFare == null
                                          ? "Select pickup and drop to calculate fare."
                                          : "Approx. Rs. ${estimatedFare!.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                        color: AppPalette.slate600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Trip Preview",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.slate900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildPreviewMap(),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPaymentMethod,
                        decoration: const InputDecoration(
                          labelText: "Payment Method",
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_rounded,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: "Cash", child: Text("Cash")),
                          DropdownMenuItem(value: "UPI", child: Text("UPI")),
                          DropdownMenuItem(value: "Card", child: Text("Card")),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            selectedPaymentMethod = value;
                          });
                        },
                      ),
                      const SizedBox(height: 22),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppPalette.primary.withOpacity(
                                canSubmit ? 0.28 : 0.14,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: canSubmit ? requestRide : null,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 54),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.1,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  bookingMode == "negotiation"
                                      ? "Negotiate Ride"
                                      : "Book Ride",
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: message.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(message),
                        padding: const EdgeInsets.only(top: 16),
                        child: ReflectionCard(
                          padding: const EdgeInsets.all(16),
                          borderRadius: BorderRadius.circular(18),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: AppPalette.slate600,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  message,
                                  style: const TextStyle(
                                    color: AppPalette.slate600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
