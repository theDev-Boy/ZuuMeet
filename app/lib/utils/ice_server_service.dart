import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

/// Fetches dynamic TURN/STUN ICE servers for global WebRTC connectivity.
///
/// Uses the **Open Relay Project** (openrelay.metered.ca) as a free, production-
/// ready TURN service — equivalent to the npm `freeice` package.
///
/// Why this matters:
///   - STUN-only can fail behind symmetric NATs (corporate/university firewalls).
///   - Open Relay runs on port 80 & 443 (universally firewall-safe).
///   - Provides TCP fallback for deep packet-filtered networks.
///   - 20 GB/month free, automatic geo-routing to the nearest relay.
///
/// Architecture:
///   1. On first call: fetch an enriched server list from Metered REST API.
///   2. Cache the result for 24 hours (servers are stable).
///   3. Always prepend Google/Cloudflare STUN servers (no auth required).
///   4. TURN servers are the fallback for peers that can't do direct P2P.
class IceServerService {
  static const String _cacheKey = 'ice_servers_cache';
  static const String _cacheTimestampKey = 'ice_servers_timestamp';
  static const int _cacheTtlMs = 24 * 60 * 60 * 1000; // 24 hours

  // Open Relay Project REST API endpoint (Metered.ca free public TURN)
  // Docs: https://www.metered.ca/tools/openrelay/
  static const String _openRelayApiUrl =
      'https://openrelay.metered.ca/api/v1/turn/credentials?apiKey=openrelayproject';

  // Static STUN servers — always included, no auth needed.
  static const List<Map<String, dynamic>> _stunServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    {'urls': 'stun:stun4.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  // Hardcoded Open Relay TURN fallback (used if API fetch fails).
  // These are the same credentials the free tier always uses.
  static const List<Map<String, dynamic>> _openRelayFallback = [
    {
      'urls': 'turn:openrelay.metered.ca:80',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': 'turns:openrelay.metered.ca:443',
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  /// Returns the full ICE server list: STUN + TURN (from API or cache or fallback).
  ///
  /// Call this once before creating an [RTCPeerConnection].
  Future<List<Map<String, dynamic>>> getIceServers() async {
    // 1. Try serving from cache first (respects TTL)
    final cached = await _loadFromCache();
    if (cached != null) {
      logger.i('[ICE] Using cached ICE servers (${cached.length} total)');
      return cached;
    }

    // 2. Try live fetch from Open Relay API
    try {
      final turnServers = await _fetchFromOpenRelay();
      final allServers = [..._stunServers, ...turnServers];
      await _saveToCache(allServers);
      logger.i('[ICE] Fetched ${turnServers.length} TURN + ${_stunServers.length} STUN servers');
      return allServers;
    } catch (e) {
      logger.w('[ICE] API fetch failed, using hardcoded fallback: $e');
    }

    // 3. Return hardcoded fallback (STUN + Open Relay static credentials)
    final fallback = [..._stunServers, ..._openRelayFallback];
    logger.i('[ICE] Using hardcoded fallback (${fallback.length} servers)');
    return fallback;
  }

  /// Fetches TURN server credentials from the Open Relay REST API.
  Future<List<Map<String, dynamic>>> _fetchFromOpenRelay() async {
    final response = await http
        .get(Uri.parse(_openRelayApiUrl))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Open Relay API returned ${response.statusCode}');
    }

    final List<dynamic> data = json.decode(response.body) as List<dynamic>;
    return data
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  /// Load ICE servers from SharedPreferences if still valid.
  Future<List<Map<String, dynamic>>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);
      if (timestamp == null) return null;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > _cacheTtlMs) {
        // Expired — clear it
        await prefs.remove(_cacheKey);
        await prefs.remove(_cacheTimestampKey);
        return null;
      }

      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;

      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      logger.w('[ICE] Cache read failed: $e');
      return null;
    }
  }

  /// Persist ICE servers to SharedPreferences.
  Future<void> _saveToCache(List<Map<String, dynamic>> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(servers));
      await prefs.setInt(
        _cacheTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      logger.w('[ICE] Cache write failed: $e');
    }
  }

  /// Force-invalidate the cache (call after a connection failure to retry fresh).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimestampKey);
    logger.i('[ICE] Cache cleared');
  }
}
