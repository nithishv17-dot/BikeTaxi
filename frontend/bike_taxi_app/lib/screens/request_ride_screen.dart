import 'package:flutter/material.dart';

class CollapsibleRideDetails extends StatelessWidget {
  // Pass your actual data model or variables here
  final String otp;
  final String bookingMode;
  final double fare;
  final double offeredFare;
  final String negotiation;
  final String paymentMethod;
  final String driverName;
  final String driverPhone;

  const CollapsibleRideDetails({
    super.key,
    required this.otp,
    required this.bookingMode,
    required this.fare,
    required this.offeredFare,
    required this.negotiation,
    required this.paymentMethod,
    required this.driverName,
    required this.driverPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1C1C), // Matches your premium dark theme
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Theme(
        // Hides the default ugly divider line in ExpansionTile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          iconColor: const Color(0xFFF4A261),
          collapsedIconColor: Colors.white54,
          title: const Text(
            "Ride Details",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // OTP Highlight Box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4A261).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFF4A261).withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "SHARE OTP WITH DRIVER",
                              style: TextStyle(
                                color: Color(0xFFF4A261),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Give this OTP to start the ride",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          otp,
                          style: const TextStyle(
                            color: Color(0xFFF4A261),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Key-Value Details
                  _buildDetailRow("Booking Mode", bookingMode),
                  _buildDetailRow("Fare", "Rs. ${fare.toStringAsFixed(2)}"),
                  _buildDetailRow("Offered Fare", offeredFare.toStringAsFixed(2)),
                  _buildDetailRow("Negotiation", negotiation),
                  _buildDetailRow("Payment Method", paymentMethod),
                  _buildDetailRow("Driver", driverName),
                  _buildDetailRow("Phone", driverPhone),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}