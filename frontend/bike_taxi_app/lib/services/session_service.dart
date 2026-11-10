import 'dart:html' as html;
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _tokenKey = 'biketaxi_token';
  static const String _userIdKey = 'biketaxi_userId';
  static const String _roleKey = 'biketaxi_role';
  static const String _nameKey = 'biketaxi_name';
  static const String _phoneKey = 'biketaxi_phone';
  static const String _sessionIdKey = 'biketaxi_sessionId';
  static const String _lastActiveKey = 'biketaxi_last_active';

  // Configurable inactivity timeout (default: 15 minutes)
  static const Duration inactivityTimeout = Duration(minutes: 15);

  static void saveSession(
    String token,
    String userId,
    String role, {
    String? sessionId,
    String? name,
    String? phone,
  }) {
    html.window.localStorage[_tokenKey] = token;
    html.window.localStorage[_userIdKey] = userId;
    html.window.localStorage[_roleKey] = role;
    if (sessionId != null && sessionId.isNotEmpty) {
      html.window.localStorage[_sessionIdKey] = sessionId;
    }
    if (name != null) {
      html.window.localStorage[_nameKey] = name;
    }
    if (phone != null) {
      html.window.localStorage[_phoneKey] = phone;
    }
    updateLastActive();

    // Sync to SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_tokenKey, token);
      prefs.setString(_userIdKey, userId);
      prefs.setString(_roleKey, role);
      if (sessionId != null) prefs.setString(_sessionIdKey, sessionId);
      if (name != null) prefs.setString(_nameKey, name);
      if (phone != null) prefs.setString(_phoneKey, phone);
    }).catchError((_) {});
  }

  static void updateLastActive() {
    html.window.localStorage[_lastActiveKey] =
        DateTime.now().millisecondsSinceEpoch.toString();
  }

  static String? getSessionId() {
    return html.window.localStorage[_sessionIdKey];
  }

  static Map<String, String>? loadSession() {
    final token = html.window.localStorage[_tokenKey];
    final userId = html.window.localStorage[_userIdKey];
    final role = html.window.localStorage[_roleKey];
    final sessionId = html.window.localStorage[_sessionIdKey];
    final name = html.window.localStorage[_nameKey];
    final phone = html.window.localStorage[_phoneKey];
    final lastActiveStr = html.window.localStorage[_lastActiveKey];

    if (token != null &&
        token.isNotEmpty &&
        userId != null &&
        userId.isNotEmpty) {
      if (lastActiveStr != null && lastActiveStr.isNotEmpty) {
        final lastActiveMillis = int.tryParse(lastActiveStr);
        if (lastActiveMillis != null) {
          final lastActiveTime =
              DateTime.fromMillisecondsSinceEpoch(lastActiveMillis);
          if (DateTime.now().difference(lastActiveTime) > inactivityTimeout) {
            // Auto-logout: session has expired due to user inactivity
            clearSession();
            return null;
          }
        }
      }

      return {
        'token': token,
        'userId': userId,
        'role': role ?? 'user',
        'sessionId': sessionId ?? '',
        'name': name ?? '',
        'phone': phone ?? '',
      };
    }
    return null;
  }

  static void clearSession() {
    html.window.localStorage.remove(_tokenKey);
    html.window.localStorage.remove(_userIdKey);
    html.window.localStorage.remove(_roleKey);
    html.window.localStorage.remove(_sessionIdKey);
    html.window.localStorage.remove(_nameKey);
    html.window.localStorage.remove(_phoneKey);
    html.window.localStorage.remove(_lastActiveKey);

    SharedPreferences.getInstance().then((prefs) {
      prefs.clear();
    }).catchError((_) {});
  }
}
