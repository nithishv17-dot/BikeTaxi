String readableLocationLabel(String? value, {required String fallback}) {
  final text = value?.trim() ?? "";
  if (text.isEmpty) {
    return fallback;
  }

  final coordinatePair = RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$');
  final coordinateSuffix = RegExp(
    r'\s*\(-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\)\s*$',
  );

  if (coordinatePair.hasMatch(text)) {
    return fallback;
  }

  if (RegExp(r'^my location\s*\(', caseSensitive: false).hasMatch(text)) {
    return "Current Location";
  }

  if (RegExp(r'^map tap\s*\(', caseSensitive: false).hasMatch(text)) {
    return fallback;
  }

  final withoutCoordinates = text.replaceFirst(coordinateSuffix, "").trim();
  return withoutCoordinates.isEmpty ? fallback : withoutCoordinates;
}
