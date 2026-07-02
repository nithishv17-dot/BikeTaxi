import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';
import '../utils/location_display.dart';
import 'ride_status_screen.dart';

class RequestRideScreen extends StatefulWidget {
  final String userId;
  final bool isEmbedded;

  const RequestRideScreen({
    super.key,
    required this.userId,
    this.isEmbedded = false,
  });

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
  bool isResolvingCurrentLocation = false;
  String? currentLocationMessage;
  double? currentLat;
  double? currentLng;

  List<Map<String, dynamic>> availableDrivers = [];
  Timer? _driversPollTimer;

  void _startDriversPolling() {
    _driversPollTimer?.cancel();
    _fetchAvailableDrivers();
    _driversPollTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _fetchAvailableDrivers();
      }
    });
  }

  void _stopDriversPolling() {
    _driversPollTimer?.cancel();
    _driversPollTimer = null;
  }

  Future<void> _fetchAvailableDrivers() async {
    try {
      final response = await ApiService.getDrivers();
      final list = List<Map<String, dynamic>>.from(
        (response["drivers"] as List<dynamic>? ?? const []).whereType<Map>(),
      );
      if (!mounted) return;
      setState(() {
        availableDrivers = list.where((d) => d["isAvailable"] == true).toList();
      });
    } catch (e) {
      print("Error fetching online drivers: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _startDriversPolling();
    _loadCurrentLocation();
    SocketService.listenDriverLocationUpdated((data) {
      if (!mounted) return;
      final driverId = data["driverId"]?.toString();
      final double? lat = data["lat"] is num
          ? (data["lat"] as num).toDouble()
          : double.tryParse("${data["lat"]}");
      final double? lng = data["lng"] is num
          ? (data["lng"] as num).toDouble()
          : double.tryParse("${data["lng"]}");

      if (driverId != null && lat != null && lng != null) {
        setState(() {
          final index = availableDrivers.indexWhere(
            (d) => d["_id"]?.toString() == driverId,
          );
          if (index != -1) {
            availableDrivers[index]["location"] = {"lat": lat, "lng": lng};
          } else {
            _fetchAvailableDrivers();
          }
        });
      }
    });
  }

  Future<void> _loadCurrentLocation() async {
    if (isResolvingCurrentLocation) return;

    setState(() {
      isResolvingCurrentLocation = true;
      currentLocationMessage = "Getting your live location...";
    });

    final pos = await LocationService.getCurrentPosition();

    if (!mounted) return;

    setState(() {
      isResolvingCurrentLocation = false;
      if (pos == null) {
        currentLocationMessage =
            "Unable to read your live location. Please allow location access.";
        return;
      }

      currentLat = pos["lat"];
      currentLng = pos["lng"];
      currentLocationMessage = null;
    });
  }

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

    // New pricing engine matching Rapido/Uber Moto
    const double baseFare = 15;
    const double baseDistanceKm = 1.5;
    const double perKmRate = 9;
    const double aboveTenKmRate = 8;
    const double platformFee = 5;
    const double gstPercent = 5;

    // Calculate distance fare
    double distanceFare = 0;
    if (distanceKm > baseDistanceKm) {
      final double remainingDistance = distanceKm - baseDistanceKm;
      if (distanceKm <= 10) {
        distanceFare = remainingDistance * perKmRate;
      } else {
        final double firstSegment = 8.5 * perKmRate; // 1.5 to 10 km
        final double remainingSegment = distanceKm - 10;
        final double secondSegment = remainingSegment * aboveTenKmRate;
        distanceFare = firstSegment + secondSegment;
      }
    }

    // Calculate total
    final double subtotal = baseFare + distanceFare;
    final double beforeGst = subtotal + platformFee;
    final double gst = beforeGst * (gstPercent / 100);
    final double totalFare = beforeGst + gst;

    return totalFare.clamp(40, 100000).toDouble();
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
    final rawAddress = suggestion["address"]?.toString() ?? "";
    final address = readableLocationLabel(
      rawAddress,
      fallback: isPickup ? "Pickup address" : "Drop address",
    );
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
    required bool hasSelectedLocation,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: hasSelectedLocation ? null : helperText,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentChip(String label, IconData icon) {
    final isSelected = selectedPaymentMethod == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedPaymentMethod = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF4A261).withOpacity(0.16) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? const Color(0xFFF4A261) : Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFFF4A261) : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFF4A261) : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferPill(String code, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4A261).withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF4A261).withOpacity(0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer_rounded, size: 16, color: Color(0xFFF4A261)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(code, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFF4A261))),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
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
      final currentLocationPoint = currentLat != null && currentLng != null
          ? LatLng(currentLat!, currentLng!)
          : null;

      if (currentLocationPoint != null) {
        return SizedBox(
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: currentLocationPoint,
                    initialZoom: 14,
                    onTap: (tapPosition, point) => _onMapTapped(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.example.bike_taxi_app",
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: currentLocationPoint,
                          width: 52,
                          height: 52,
                          child: const Icon(
                            Icons.my_location_rounded,
                            size: 38,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                        ...availableDrivers
                            .map((driver) {
                              final loc = driver["location"];
                              final double? lat =
                                  loc != null && loc["lat"] is num
                                  ? (loc["lat"] as num).toDouble()
                                  : (loc != null && loc["lat"] is String
                                        ? double.tryParse(loc["lat"])
                                        : null);
                              final double? lng =
                                  loc != null && loc["lng"] is num
                                  ? (loc["lng"] as num).toDouble()
                                  : (loc != null && loc["lng"] is String
                                        ? double.tryParse(loc["lng"])
                                        : null);
                              if (lat == null || lng == null) {
                                return const Marker(
                                  point: LatLng(0, 0),
                                  child: SizedBox.shrink(),
                                );
                              }

                              return Marker(
                                point: LatLng(lat, lng),
                                width: 40,
                                height: 40,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: AppPalette.primary,
                                      width: 2.2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.directions_bike_rounded,
                                    color: AppPalette.primary,
                                    size: 20,
                                  ),
                                ),
                              );
                            })
                            .where((m) => m.point.latitude != 0.0),
                      ],
                    ),
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
                      color: Colors.black.withOpacity(0.6),
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
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      "Centered on your live location",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (isResolvingCurrentLocation) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Loading your live location for the map preview...",
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

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.map_outlined, color: Color(0xFF64748B)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                currentLocationMessage ??
                    "Enable location access so the preview starts from your live position.",
                style: const TextStyle(
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
      ...availableDrivers
          .map((driver) {
            final loc = driver["location"];
            final double? lat = loc != null && loc["lat"] is num
                ? (loc["lat"] as num).toDouble()
                : (loc != null && loc["lat"] is String
                      ? double.tryParse(loc["lat"])
                      : null);
            final double? lng = loc != null && loc["lng"] is num
                ? (loc["lng"] as num).toDouble()
                : (loc != null && loc["lng"] is String
                      ? double.tryParse(loc["lng"])
                      : null);
            if (lat == null || lng == null) {
              return const Marker(
                point: LatLng(0, 0),
                child: SizedBox.shrink(),
              );
            }

            return Marker(
              point: LatLng(lat, lng),
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(color: AppPalette.primary, width: 2.2),
                ),
                child: const Icon(
                  Icons.directions_bike_rounded,
                  color: AppPalette.primary,
                  size: 20,
                ),
              ),
            );
          })
          .where((m) => m.point.latitude != 0.0),
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
                  color: Colors.black.withOpacity(0.6),
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
      const label = "Resolving pickup address...";
      setState(() {
        pickupLat = point.latitude;
        pickupLng = point.longitude;
        pickupAddress = label;
        pickupController.text = label;
        pickupInput = label;
        pickupPlaceId = "map_tap_pickup";
        pickupError = null;
        message = "Finding pickup address...";
      });
      _reverseGeocodeAndUpdate(
        point.latitude,
        point.longitude,
        isPickup: true,
        fallbackAddress: "Pickup address from map",
      );
    } else {
      const label = "Resolving drop address...";
      setState(() {
        dropLat = point.latitude;
        dropLng = point.longitude;
        dropAddress = label;
        destinationController.text = label;
        dropInput = label;
        dropPlaceId = "map_tap_drop";
        dropError = null;
        message = "Finding drop address...";
      });
      _reverseGeocodeAndUpdate(
        point.latitude,
        point.longitude,
        isPickup: false,
        fallbackAddress: "Drop address from map",
      );
    }
  }

  Future<void> _reverseGeocodeAndUpdate(
    double lat,
    double lng, {
    required bool isPickup,
    required String fallbackAddress,
  }) async {
    var nextAddress = fallbackAddress;
    try {
      final result = await ApiService.reversePhotonPlace(lat, lng);
      if (!mounted) return;

      final bestAddress = result?["address"]?.toString();
      if (bestAddress != null && bestAddress.isNotEmpty) {
        nextAddress = readableLocationLabel(
          bestAddress,
          fallback: fallbackAddress,
        );
      }
    } catch (_) {
      // Keep a worded address fallback if reverse geocoding fails.
    }

    if (!mounted) return;

    setState(() {
      if (isPickup) {
        pickupAddress = nextAddress;
        pickupController.text = nextAddress;
        pickupInput = nextAddress;
        pickupError = null;
        message = "Pickup address set";
      } else {
        dropAddress = nextAddress;
        destinationController.text = nextAddress;
        dropInput = nextAddress;
        dropError = null;
        message = "Drop address set";
      }
    });
  }

  Future<void> _selectCurrentPickupAddress(Map<String, double> pos) async {
    const label = "Resolving current address...";
    _selectSuggestion({
      "placeId": "gps_current_loc",
      "address": label,
      "lat": pos['lat'],
      "lng": pos['lng'],
    }, isPickup: true);

    setState(() {
      currentLat = pos['lat'];
      currentLng = pos['lng'];
      message = "Finding your current address...";
    });

    await _reverseGeocodeAndUpdate(
      pos['lat']!,
      pos['lng']!,
      isPickup: true,
      fallbackAddress: "Current pickup address",
    );
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
              _buildFareDetailRow(
                "Distance Charge",
                "Rs. ${((fare - 40).clamp(0, 100000)).toStringAsFixed(2)}",
              ),
              const Divider(height: 24),
              _buildFareDetailRow(
                "Total Estimated Fare",
                "Rs. ${fare.toStringAsFixed(2)}",
                isTotal: true,
              ),
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

  Widget _buildFareDetailRow(
    String label,
    String value, {
    bool isTotal = false,
  }) {
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

      String errMessage = e.toString().replaceFirst("Exception: ", "");
      if (errMessage.toLowerCase().contains("no drivers available")) {
        errMessage =
            "No drivers are currently available. Please try again later.";
      }

      setState(() {
        message = errMessage;
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
    _stopDriversPolling();
    SocketService.stopListeningDriverLocationUpdated();
    pickupDebounce?.cancel();
    dropDebounce?.cancel();
    pickupController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = PremiumBackdrop(
      accentColor: const Color(0xFFF4A261),
      secondaryColor: const Color(0xFFFFB86B),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "Good Evening 👋",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Nithish",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                          ),
                          child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.location_on_rounded, color: Color(0xFFF4A261), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Current Location",
                                  style: TextStyle(fontSize: 11, color: Colors.white70),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Coimbatore",
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildPreviewMap(),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RevealMotion(
                      delay: const Duration(milliseconds: 120),
                      child: ReflectionCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    "Where are you going?",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (pickupAddress != null && dropAddress != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4A261).withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      "Ready",
                                      style: TextStyle(
                                        color: Color(0xFFF4A261),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildLocationSearchField(
                              label: "Pickup",
                              hintText: "Enter pickup location",
                              helperText: "Tap a suggestion or use your live location",
                              controller: pickupController,
                              onChanged: _onPickupChanged,
                              isSearching: isSearchingPickup,
                              errorText: pickupError,
                              icon: Icons.my_location_rounded,
                              hasSelectedLocation: pickupAddress != null,
                            ),
                            if (pickupAddress == null) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ActionChip(
                                    avatar: const Icon(Icons.gps_fixed_rounded, size: 16, color: Color(0xFFF4A261)),
                                    label: const Text("Use Live Location"),
                                    onPressed: isResolvingCurrentLocation
                                        ? null
                                        : () async {
                                            setState(() {
                                              message = "Getting your location...";
                                            });
                                            final pos = await LocationService.getCurrentPosition();
                                            if (!mounted) return;
                                            if (pos != null) {
                                              await _selectCurrentPickupAddress(pos);
                                            } else {
                                              setState(() {
                                                message = "Could not get your location. Please allow location access.";
                                              });
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ],
                            _buildSuggestionsList(pickupSuggestions, isPickup: true),
                            const SizedBox(height: 10),
                            _buildLocationSearchField(
                              label: "Drop",
                              hintText: "Enter destination",
                              helperText: "Choose a drop point to continue",
                              controller: destinationController,
                              onChanged: _onDropChanged,
                              isSearching: isSearchingDrop,
                              errorText: dropError,
                              icon: Icons.flag_rounded,
                              hasSelectedLocation: dropAddress != null,
                            ),
                            _buildSuggestionsList(dropSuggestions, isPickup: false),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        bookingMode = bookingMode == "normal" ? "negotiation" : "normal";
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            bookingMode == "normal" ? Icons.flash_on_rounded : Icons.handshake_rounded,
                                            color: const Color(0xFFF4A261),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              bookingMode == "normal" ? "Normal Booking" : "Negotiation Mode",
                                              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                                            ),
                                          ),
                                          const Icon(Icons.swap_horiz_rounded, color: Colors.white70),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    RevealMotion(
                      delay: const Duration(milliseconds: 180),
                      child: ReflectionCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    "Estimated Fare",
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: estimatedFare == null ? null : _showFareBreakdown,
                                  child: Text(
                                    estimatedFare == null ? "Tap to calculate" : "Breakdown",
                                    style: const TextStyle(color: Color(0xFFF4A261), fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.currency_rupee_rounded, color: Color(0xFFF4A261), size: 28),
                                const SizedBox(width: 8),
                                Text(
                                  estimatedFare == null ? "--" : estimatedFare!.toStringAsFixed(2),
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    "Includes platform fee and GST",
                                    style: TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    RevealMotion(
                      delay: const Duration(milliseconds: 220),
                      child: ReflectionCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Payment",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _buildPaymentChip("Cash", Icons.money_rounded),
                                _buildPaymentChip("UPI", Icons.qr_code_rounded),
                                _buildPaymentChip("Card", Icons.credit_card_rounded),
                                _buildPaymentChip("Wallet", Icons.account_balance_wallet_rounded),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    RevealMotion(
                      delay: const Duration(milliseconds: 260),
                      child: ReflectionCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Offers",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildOfferPill("SAVE20", "Flat ₹20 Off"),
                                  const SizedBox(width: 10),
                                  _buildOfferPill("FIRST50", "50% Off First Ride"),
                                  const SizedBox(width: 10),
                                  _buildOfferPill("RIDEPASS", "Ride Pass Available"),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF4A261).withOpacity(canSubmit ? 0.26 : 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: canSubmit ? requestRide : null,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 58),
                          backgroundColor: const Color(0xFFF4A261),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                          elevation: 0,
                        ),
                        icon: isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black))
                            : const Icon(Icons.bike_scooter_rounded),
                        label: Text(
                          isLoading
                              ? "Searching riders..."
                              : bookingMode == "negotiation"
                                  ? "Request Negotiation"
                                  : "Book Ride",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
                                    const Icon(Icons.info_outline_rounded, color: Color(0xFFF4A261)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        message,
                                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
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
          ],
        ),
      ),
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Request Ride")),
      body: content,
    );
  }
}
