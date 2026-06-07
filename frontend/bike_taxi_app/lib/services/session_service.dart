import 'dart:html' as html;

class SessionService {
  static const String _tokenKey = 'biketaxi_token';
  static const String _userIdKey = 'biketaxi_userId';
  static const String _roleKey = 'biketaxi_role';

  static void saveSession(String token, String userId, String role) {
    html.window.localStorage[_tokenKey] = token;
    html.window.localStorage[_userIdKey] = userId;
    html.window.localStorage[_roleKey] = role;
  }

  static Map<String, String>? loadSession() {
    final token = html.window.localStorage[_tokenKey];
    final userId = html.window.localStorage[_userIdKey];
    final role = html.window.localStorage[_roleKey];
    if (token != null && token.isNotEmpty && userId != null && userId.isNotEmpty) {
      return {'token': token, 'userId': userId, 'role': role ?? 'user'};
    }
    return null;
  }

  static void clearSession() {
    html.window.localStorage.remove(_tokenKey);
    html.window.localStorage.remove(_userIdKey);
    html.window.localStorage.remove(_roleKey);
  }
}
