import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/user_model.dart';
import '../models/match_model.dart';
import '../models/report_model.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Handles all Firebase Realtime Database operations.
/// Firebase serves as the complete backend – no separate server needed.
class DatabaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ---------------------------------------------------------------------------
  // USER OPERATIONS
  // ---------------------------------------------------------------------------

  /// Create or update a user profile.
  Future<void> saveUser(UserModel user) async {
    try {
      await _db
          .ref(AppConstants.usersPath)
          .child(user.uid)
          .set(user.toJson());
    } catch (e) {
      logger.e('Failed to save user', error: e);
      rethrow;
    }
  }

  /// Update specific user fields.
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      await _db.ref(AppConstants.usersPath).child(uid).update(data);
    } catch (e) {
      logger.e('Failed to update user', error: e);
      rethrow;
    }
  }

  /// Fetch a user by UID.
  Future<UserModel?> getUser(String uid) async {
    try {
      final snapshot =
          await _db.ref(AppConstants.usersPath).child(uid).get();
      if (!snapshot.exists || snapshot.value == null) return null;
      return UserModel.fromJson(
        snapshot.value as Map<dynamic, dynamic>,
        uid,
      );
    } catch (e) {
      logger.e('Failed to get user', error: e);
      return null;
    }
  }

  /// Set user online/offline status and update lastActive.
  Future<void> setOnlineStatus(String uid, bool isOnline) async {
    await updateUser(uid, {
      'isOnline': isOnline,
      'lastActive': ServerValue.timestamp,
    });
  }

  /// Set up on-disconnect to auto-remove from active_users and set offline.
  void setupPresence(String uid) {
    final userStatusRef =
        _db.ref(AppConstants.usersPath).child(uid);
    final activeRef =
        _db.ref(AppConstants.activeUsersPath).child(uid);

    // When the client disconnects, clean up.
    userStatusRef.onDisconnect().update({
      'isOnline': false,
      'isSearching': false,
      'lastActive': ServerValue.timestamp,
    });
    activeRef.onDisconnect().remove();
  }

  // ---------------------------------------------------------------------------
  // ACTIVE USERS / MATCHMAKING QUEUE
  // ---------------------------------------------------------------------------

  /// Add current user to the searching queue.
  Future<void> joinSearchQueue(UserModel user) async {
    try {
      await _db
          .ref(AppConstants.activeUsersPath)
          .child(user.uid)
          .set({
        'status': 'searching',
        'gender': user.gender,
        'age': user.age,
        'country': user.countryCode,
        'name': user.name,
        'joinedAt': ServerValue.timestamp,
      });
      await updateUser(user.uid, {'isSearching': true});
    } catch (e) {
      logger.e('Failed to join search queue', error: e);
      rethrow;
    }
  }

  /// Remove current user from the searching queue.
  Future<void> leaveSearchQueue(String uid) async {
    try {
      await _db
          .ref(AppConstants.activeUsersPath)
          .child(uid)
          .remove();
      await updateUser(uid, {'isSearching': false});
    } catch (e) {
      logger.e('Failed to leave search queue', error: e);
    }
  }

  /// Find a compatible partner from the active users queue.
  /// Gender preference matching: if user wants "Women" only match "Female", etc.
  Future<Map<String, dynamic>?> findPartner(UserModel currentUser) async {
    try {
      final snapshot =
          await _db.ref(AppConstants.activeUsersPath).get();
      if (!snapshot.exists || snapshot.value == null) return null;

      final activeUsers = snapshot.value as Map<dynamic, dynamic>;

      for (final entry in activeUsers.entries) {
        final partnerUid = entry.key as String;
        if (partnerUid == currentUser.uid) continue;

        final partnerData = entry.value as Map<dynamic, dynamic>;
        final partnerStatus = partnerData['status'] as String? ?? '';
        
        // ONLY match with people explicitly searching
        if (partnerStatus != 'searching') continue;

        // Skip blocked users
        if (currentUser.blockedUsers.contains(partnerUid)) continue;

        return {
          'uid': partnerUid,
          'name': partnerData['name'] as String? ?? 'Anonymous',
          'gender': partnerData['gender'] as String? ?? '',
          'country': partnerData['country'] as String? ?? '',
        };
      }
      return null;
    } catch (e) {
      logger.e('Failed to find partner', error: e);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // MATCHES
  // ---------------------------------------------------------------------------

  /// Create a new match and return the match ID.
  Future<String> createMatch({
    required String user1,
    required String user2,
    required String user1Name,
    required String user2Name,
  }) async {
    try {
      final matchRef = _db.ref(AppConstants.matchesPath).push();
      final matchId = matchRef.key!;
      final match = MatchModel(
        matchId: matchId,
        user1: user1,
        user2: user2,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        status: 'active',
        initiator: user1,
        user1Name: user1Name,
        user2Name: user2Name,
      );
      await matchRef.set(match.toJson());

      // Mark both users as matched (not searching)
      await _db
          .ref(AppConstants.activeUsersPath)
          .child(user1)
          .update({'status': 'matched', 'matchId': matchId});
      await _db
          .ref(AppConstants.activeUsersPath)
          .child(user2)
          .update({'status': 'matched', 'matchId': matchId});

      return matchId;
    } catch (e) {
      logger.e('Failed to create match', error: e);
      rethrow;
    }
  }

  /// Update match fields.
  Future<void> updateMatch(String matchId, Map<String, dynamic> data) async {
    try {
      await _db.ref(AppConstants.matchesPath).child(matchId).update(data);
    } catch (e) {
      logger.e('Failed to update match', error: e);
    }
  }

  /// End a match.
  Future<void> endMatch(String matchId) async {
    try {
      await _db.ref(AppConstants.matchesPath).child(matchId).update({
        'status': 'ended',
        'endedAt': ServerValue.timestamp,
      });
    } catch (e) {
      logger.e('Failed to end match', error: e);
    }
  }

  /// Listen for when current user gets matched by someone else.
  Stream<DatabaseEvent> listenForMatch(String uid) {
    return _db
        .ref(AppConstants.activeUsersPath)
        .child(uid)
        .onValue;
  }

  /// Get match data.
  Future<MatchModel?> getMatch(String matchId) async {
    try {
      final snapshot =
          await _db.ref(AppConstants.matchesPath).child(matchId).get();
      if (!snapshot.exists || snapshot.value == null) return null;
      return MatchModel.fromJson(
        snapshot.value as Map<dynamic, dynamic>,
        matchId,
      );
    } catch (e) {
      logger.e('Failed to get match', error: e);
      return null;
    }
  }

  Future<Map<String, dynamic>> createDirectCall({
    required UserModel caller,
    required String calleeUid,
    required String calleeName,
    required String calleeAvatar,
    required bool isVideo,
  }) async {
    final matchRef = _db.ref(AppConstants.matchesPath).push();
    final matchId = matchRef.key!;
    final channelParts = [caller.uid, calleeUid]..sort();
    final channelName = channelParts.join('_');
    final now = DateTime.now().millisecondsSinceEpoch;
    final callType = isVideo ? 'video' : 'audio';

    final matchData = {
      'user1': caller.uid,
      'user2': calleeUid,
      'startedAt': now,
      'status': 'ringing',
      'initiator': caller.uid,
      'user1Name': caller.name,
      'user2Name': calleeName,
      'callType': callType,
      'channelName': channelName,
      'isDirectCall': true,
      'callerAvatar': caller.avatarUrl,
      'calleeAvatar': calleeAvatar,
    };

    final callPayload = <String, dynamic>{
      'type': 'call',
      'callId': matchId,
      'matchId': matchId,
      'callType': callType,
      'channelName': channelName,
      'callerId': caller.uid,
      'callerName': caller.name,
      'callerAvatar': caller.avatarUrl,
      'calleeUid': calleeUid,
      'calleeName': calleeName,
      'calleeAvatar': calleeAvatar,
      'timestamp': now.toString(),
    };

    await matchRef.set(matchData);
    await _db
        .ref(AppConstants.directCallsPath)
        .child(calleeUid)
        .set(callPayload);

    return callPayload;
  }

  Future<void> acceptDirectCall({
    required String myUid,
    required String matchId,
  }) async {
    await _db.ref(AppConstants.matchesPath).child(matchId).update({
      'status': 'connected',
      'answeredAt': ServerValue.timestamp,
    });
    await _db.ref(AppConstants.directCallsPath).child(myUid).remove();
  }

  Future<void> rejectDirectCall({
    required String myUid,
    required String matchId,
    String status = 'declined',
  }) async {
    await _db.ref(AppConstants.matchesPath).child(matchId).update({
      'status': status,
      'endedAt': ServerValue.timestamp,
    });
    await _db.ref(AppConstants.directCallsPath).child(myUid).remove();
    if (status == 'missed' || status == 'no_answer' || status == 'declined') {
      unawaited(_addCallEventToChat(matchId, status));
    }
  }

  Future<void> endDirectCall(String matchId) async {
    await _db.ref(AppConstants.matchesPath).child(matchId).update({
      'status': 'ended',
      'endedAt': ServerValue.timestamp,
    });
  }

  /// Listen for match status changes (e.g., partner ended call).
  Stream<DatabaseEvent> listenForMatchStatus(String matchId) {
    return _db
        .ref(AppConstants.matchesPath)
        .child(matchId)
        .child('status')
        .onValue;
  }

  Future<void> _addCallEventToChat(String matchId, String status) async {
    try {
      final matchSnap = await _db.ref(AppConstants.matchesPath).child(matchId).get();
      if (!matchSnap.exists || matchSnap.value == null) return;
      if (matchSnap.value is! Map) return;
      final match = Map<dynamic, dynamic>.from(matchSnap.value as Map);
      final user1 = (match['user1'] ?? '').toString();
      final user2 = (match['user2'] ?? '').toString();
      if (user1.isEmpty || user2.isEmpty) return;
      final users = [user1, user2]..sort();
      final chatId = users.join('_');
      final now = DateTime.now().millisecondsSinceEpoch;
      final callType = (match['callType'] ?? 'call').toString();
      final text = switch (status) {
        'missed' || 'no_answer' => 'Missed $callType call',
        'declined' => '$callType call declined',
        _ => '$callType call ended',
      };

      final msgRef = _db.ref('chats').child(chatId).child('messages').push();
      await msgRef.set({
        'id': msgRef.key,
        'senderId': 'system',
        'text': text,
        'type': 'callEvent',
        'timestamp': now,
        'isEdited': false,
        'deletedFor': <String>[],
        'status': 'seen',
      });

      final metaRef = _db.ref('chats_meta').child(chatId);
      final metaSnap = await metaRef.get();
      final metaMap = metaSnap.value is Map
          ? Map<dynamic, dynamic>.from(metaSnap.value as Map)
          : <dynamic, dynamic>{};
      final currentUnread = metaMap['unreadCounts'] is Map
          ? Map<String, dynamic>.from(metaMap['unreadCounts'] as Map)
          : <String, dynamic>{};
      final unreadCounts = <String, int>{
        user1: (currentUnread[user1] as num?)?.toInt() ?? 0,
        user2: (currentUnread[user2] as num?)?.toInt() ?? 0,
      };
      await metaRef.update({
        'participants': [user1, user2],
        'lastMessage': text,
        'lastMessageTime': now,
        'unreadCounts': unreadCounts,
      });
    } catch (e) {
      logger.w('Failed to append call event to chat: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // REPORTS & BLOCKING
  // ---------------------------------------------------------------------------

  /// Submit a report.
  Future<void> submitReport(ReportModel report) async {
    try {
      await _db
          .ref(AppConstants.reportsPath)
          .child(report.reportId)
          .set(report.toJson());
    } catch (e) {
      logger.e('Failed to submit report', error: e);
      rethrow;
    }
  }

  /// Block a user.
  Future<void> blockUser(String myUid, String blockedUid) async {
    try {
      // Add to blocked list in user's profile
      final userRef =
          _db.ref(AppConstants.usersPath).child(myUid).child('blockedUsers');
      final snapshot = await userRef.get();
      List<String> blocked = [];
      if (snapshot.exists && snapshot.value != null) {
        blocked = (snapshot.value as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      }
      if (!blocked.contains(blockedUid)) {
        blocked.add(blockedUid);
        await userRef.set(blocked);
      }
    } catch (e) {
      logger.e('Failed to block user', error: e);
      rethrow;
    }
  }

  /// Unblock a user.
  Future<void> unblockUser(String myUid, String blockedUid) async {
    try {
      final userRef =
          _db.ref(AppConstants.usersPath).child(myUid).child('blockedUsers');
      final snapshot = await userRef.get();
      if (snapshot.exists && snapshot.value != null) {
        List<String> blocked = (snapshot.value as List<dynamic>)
            .map((e) => e.toString())
            .toList();
        if (blocked.contains(blockedUid)) {
          blocked.remove(blockedUid);
          await userRef.set(blocked);
        }
      }
    } catch (e) {
      logger.e('Failed to unblock user', error: e);
      rethrow;
    }
  }

  /// Check if user is banned.
  Future<bool> isUserBanned(String uid) async {
    try {
      final snapshot =
          await _db.ref(AppConstants.bannedUsersPath).child(uid).get();
      return snapshot.exists;
    } catch (e) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // FRIENDS SYSTEM
  // ---------------------------------------------------------------------------

  /// Send a friend request.
  Future<void> sendFriendRequest(String senderUid, String receiverUid) async {
    try {
      final receiverRef = _db.ref(AppConstants.usersPath).child(receiverUid).child('friendRequests');
      final snapshot = await receiverRef.get();
      List<String> requests = [];
      if (snapshot.exists && snapshot.value != null) {
        requests = (snapshot.value as List<dynamic>).map((e) => e.toString()).toList();
      }
      if (!requests.contains(senderUid)) {
        requests.add(senderUid);
        await receiverRef.set(requests);
      }
    } catch (e) {
      logger.e('Failed to send friend request', error: e);
      rethrow;
    }
  }

  /// Accept a friend request.
  Future<void> acceptFriendRequest(String myUid, String senderUid) async {
    try {
      // 1. Remove from requests
      final myRequestsRef = _db.ref(AppConstants.usersPath).child(myUid).child('friendRequests');
      final reqSnapshot = await myRequestsRef.get();
      if (reqSnapshot.exists && reqSnapshot.value != null) {
        List<String> requests = (reqSnapshot.value as List<dynamic>).map((e) => e.toString()).toList();
        requests.remove(senderUid);
        await myRequestsRef.set(requests);
      }

      // 2. Add to my friends
      final myFriendsRef = _db.ref(AppConstants.usersPath).child(myUid).child('friends');
      final myFrSnapshot = await myFriendsRef.get();
      List<String> myFriends = [];
      if (myFrSnapshot.exists && myFrSnapshot.value != null) {
        myFriends = (myFrSnapshot.value as List<dynamic>).map((e) => e.toString()).toList();
      }
      if (!myFriends.contains(senderUid)) {
        myFriends.add(senderUid);
        await myFriendsRef.set(myFriends);
      }

      // 3. Add to sender's friends
      final senderFriendsRef = _db.ref(AppConstants.usersPath).child(senderUid).child('friends');
      final senderFrSnapshot = await senderFriendsRef.get();
      List<String> senderFriends = [];
      if (senderFrSnapshot.exists && senderFrSnapshot.value != null) {
        senderFriends = (senderFrSnapshot.value as List<dynamic>).map((e) => e.toString()).toList();
      }
      if (!senderFriends.contains(myUid)) {
        senderFriends.add(myUid);
        await senderFriendsRef.set(senderFriends);
      }
    } catch (e) {
      logger.e('Failed to accept friend request', error: e);
      rethrow;
    }
  }

  /// Reject a friend request.
  Future<void> rejectFriendRequest(String myUid, String senderUid) async {
    try {
      final myRequestsRef = _db.ref(AppConstants.usersPath).child(myUid).child('friendRequests');
      final reqSnapshot = await myRequestsRef.get();
      if (reqSnapshot.exists && reqSnapshot.value != null) {
        List<String> requests = (reqSnapshot.value as List<dynamic>).map((e) => e.toString()).toList();
        requests.remove(senderUid);
        await myRequestsRef.set(requests);
      }
    } catch (e) {
      logger.e('Failed to reject friend request', error: e);
      rethrow;
    }
  }

  /// Remove a friend.
  Future<void> removeFriend(String myUid, String friendUid) async {
    try {
      // 1. Remove from my friends
      final myFriendsRef = _db.ref(AppConstants.usersPath).child(myUid).child('friends');
      final myFrSnapshot = await myFriendsRef.get();
      if (myFrSnapshot.exists && myFrSnapshot.value != null) {
        List<String> myFriends = (myFrSnapshot.value as List<dynamic>).map((e) => e.toString()).toList();
        myFriends.remove(friendUid);
        await myFriendsRef.set(myFriends);
      }

      // 2. Remove from their friends
      final senderFriendsRef = _db.ref(AppConstants.usersPath).child(friendUid).child('friends');
      final senderFrSnapshot = await senderFriendsRef.get();
      if (senderFrSnapshot.exists && senderFrSnapshot.value != null) {
        List<String> senderFriends = (senderFrSnapshot.value as List<dynamic>).map((e) => e.toString()).toList();
        senderFriends.remove(myUid);
        await senderFriendsRef.set(senderFriends);
      }
    } catch (e) {
      logger.e('Failed to remove friend', error: e);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // CALL HISTORY
  // ---------------------------------------------------------------------------

  /// Get call history for a user.
  Future<List<MatchModel>> getCallHistory(String uid) async {
    try {
      final snapshot = await _db
          .ref(AppConstants.matchesPath)
          .orderByChild('status')
          .equalTo('ended')
          .get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final matches = snapshot.value as Map<dynamic, dynamic>;
      final history = <MatchModel>[];

      for (final entry in matches.entries) {
        final data = entry.value as Map<dynamic, dynamic>;
        if (data['user1'] == uid || data['user2'] == uid) {
          history.add(MatchModel.fromJson(data, entry.key as String));
        }
      }

      // Sort by startedAt descending
      history.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return history;
    } catch (e) {
      logger.e('Failed to get call history', error: e);
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // GLOBAL USER DISCOVERY
  // ---------------------------------------------------------------------------

  /// Fetch all users in the system (for manual discovery).
  Future<List<UserModel>> getAllUsers() async {
    try {
      final snapshot = await _db.ref(AppConstants.usersPath).get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.entries.map((e) {
        return UserModel.fromJson(e.value as Map<dynamic, dynamic>, e.key as String);
      }).toList();
    } catch (e) {
      logger.e('Failed to get all users', error: e);
      return [];
    }
  }

  /// Find a user by their unique 6-digit displayId.
  Future<UserModel?> getUserByDisplayId(String displayId) async {
    try {
      final snapshot = await _db
          .ref(AppConstants.usersPath)
          .orderByChild('displayId')
          .equalTo(displayId)
          .get();

      if (!snapshot.exists || snapshot.value == null) return null;

      final data = snapshot.value as Map<dynamic, dynamic>;
      if (data.isEmpty) return null;

      final entry = data.entries.first;
      return UserModel.fromJson(entry.value as Map<dynamic, dynamic>, entry.key as String);
    } catch (e) {
      logger.e('Failed to get user by displayId', error: e);
      return null;
    }
  }
}
