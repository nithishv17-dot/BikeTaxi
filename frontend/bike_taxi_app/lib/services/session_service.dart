import 'dart:html' as html;

class SessionService {
  static const String _tokenKey = 'biketaxi_token';
  static const String _userIdKey = 'biketaxi_userId';
  static const String _roleKey = 'biketaxi_role';
  static const String _nameKey = 'biketaxi_name';
  static const String _phoneKey = 'biketaxi_phone';
  static const String _lastActiveKey = 'biketaxi_last_active';

  // Configurable inactivity timeout (default: 15 minutes)
  static const Duration inactivityTimeout = Duration(minutes: 15);

  static void saveSession(String token, String userId, String role, {String? name, String? phone}) {
    html.window.localStorage[_tokenKey] = token;
    html.window.localStorage[_userIdKey] = userId;
    html.window.localStorage[_roleKey] = role;
    if (name != null) {
      html.window.localStorage[_nameKey] = name;
    }
    if (phone != null) {
      html.window.localStorage[_phoneKey] = phone;
    }
    updateLastActive();
  }

  static void updateLastActive() {
    html.window.localStorage[_lastActiveKey] = DateTime.now().millisecondsSinceEpoch.toString();
  }

  static Map<String, String>? loadSession() {
    final token = html.window.localStorage[_tokenKey];
    final userId = html.window.localStorage[_userIdKey];
    final role = html.window.localStorage[_roleKey];
    final name = html.window.localStorage[_nameKey];
    final phone = html.window.localStorage[_phoneKey];
    final lastActiveStr = html.window.localStorage[_lastActiveKey];

    if (token != null && token.isNotEmpty && userId != null && userId.isNotEmpty) {
      if (lastActiveStr != null && lastActiveStr.isNotEmpty) {
        final lastActiveMillis = int.tryParse(lastActiveStr);
        if (lastActiveMillis != null) {
          final lastActiveTime = DateTime.fromMillisecondsSinceEpoch(lastActiveMillis);
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
    html.window.localStorage.remove(_nameKey);
    html.window.localStorage.remove(_phoneKey);
    html.window.localStorage.remove(_lastActiveKey);
  }
}
