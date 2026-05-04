import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Detects the user's country via lightning-fast IP geolocation.
/// We do not ask for exact GPS permission on sign-up to improve conversion rate.
class LocationService {
  static const _countryKey = 'cached_country';
  static const _countryCodeKey = 'cached_country_code';

  /// Get the user's country. Returns a map with 'country' and 'countryCode'.
  Future<Map<String, String>> getCountry() async {
    // 1. Try cached first
    final cached = await _getCached();
    if (cached != null) return cached;

    // 2. Try IP Geolocation (Primary)
    try {
      final ip = await _getFromIP();
      if (ip != null) {
        await _cache(ip);
        return ip;
      }
    } catch (e) {
      logger.w('IP country detection failed', error: e);
    }

    // Fallback if no network
    return {'country': 'Unknown Location', 'countryCode': ''};
  }

  Future<Map<String, String>?> _getFromIP() async {
    try {
      // First try freeipapi (HTTPS)
      var response = await http
          .get(Uri.parse('https://freeipapi.com/api/json'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'country': data['countryName'] as String? ?? 'Unknown Location',
          'countryCode': data['countryCode'] as String? ?? '',
        };
      }

      // Fallback to ipapi.co (HTTPS)
      response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'country': data['country_name'] as String? ?? 'Unknown Location',
          'countryCode': data['country_code'] as String? ?? '',
        };
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, String>?> _getCached() async {
    final prefs = await SharedPreferences.getInstance();
    final country = prefs.getString(_countryKey);
    final code = prefs.getString(_countryCodeKey);
    if (country != null && code != null) {
      return {'country': country, 'countryCode': code};
    }
    return null;
  }

  Future<void> _cache(Map<String, String> data) async {
    if (data['countryCode'] == null || data['countryCode']!.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_countryKey, data['country']!);
    await prefs.setString(_countryCodeKey, data['countryCode']!);
  }
}
