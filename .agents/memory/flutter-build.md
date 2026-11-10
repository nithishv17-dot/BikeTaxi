---
name: Flutter Build in Replit
description: How to build the Flutter web app in this Replit environment
---

Flutter 3.32.0 is available via `installSystemDependencies({ packages: ["flutter"] })`.
Dart SDK version is 3.8.0, so pubspec.yaml must use `sdk: ^3.5.0` (not ^3.11.1).

Build command: `cd frontend/bike_taxi_app && flutter pub get && flutter build web --release`
Output goes to: `frontend/bike_taxi_app/build/web/`
The Node.js backend (backend/server.js) serves that directory as static files.

**Why:** The Replit nix channel provides Flutter 3.32.0 with Dart 3.8.0, not the latest Dart 3.11+.
**How to apply:** Always update pubspec SDK constraint before running pub get when the version doesn't match.
