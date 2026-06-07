import 'dart:async';
import 'dart:html' as html;

class LocationService {
  static Future<Map<String, double>?> getCurrentPosition() async {
    try {
      final completer = Completer<Map<String, double>?>();

      html.window.navigator.geolocation.getCurrentPosition().then((position) {
        completer.complete({
          'lat': position.coords!.latitude!.toDouble(),
          'lng': position.coords!.longitude!.toDouble(),
        });
      }).catchError((error) {
        print('Geolocation error: $error');
        completer.complete(null);
      });

      return completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
    } catch (e) {
      print('Location service error: $e');
      return null;
    }
  }
}
