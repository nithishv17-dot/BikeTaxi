import 'dart:html' as html;

class SessionService {
  static const String _tokenKey = 'biketaxi_token';
  static const String _userIdKey = 'biketaxi_userId';
  static const String _roleKey = 'biketaxi_role';
  static const String _nameKey = 'biketaxi_name';
  static const String _phoneKey = 'biketaxi_phone';

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
  }

  static Map<String, String>? loadSession() {
    final token = html.window.localStorage[_tokenKey];
    final userId = html.window.localStorage[_userIdKey];
    final role = html.window.localStorage[_roleKey];
    final name = html.window.localStorage[_nameKey];
    final phone = html.window.localStorage[_phoneKey];
    if (token != null && token.isNotEmpty && userId != null && userId.isNotEmpty) {
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
  }
}
