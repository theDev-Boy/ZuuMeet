import 'package:equatable/equatable.dart';

/// Represents a match between two users for a video call.
class MatchModel extends Equatable {
  final String matchId;
  final String user1;
  final String user2;
  final int startedAt;
  final int? endedAt;
  final String status; // 'waiting', 'active', 'ended'
  final String initiator;
  final String? user1Name;
  final String? user2Name;

  const MatchModel({
    required this.matchId,
    required this.user1,
    required this.user2,
    required this.startedAt,
    this.endedAt,
    this.status = 'waiting',
    required this.initiator,
    this.user1Name,
    this.user2Name,
  });

  factory MatchModel.fromJson(Map<dynamic, dynamic> json, String matchId) {
    return MatchModel(
      matchId: matchId,
      user1: json['user1'] as String? ?? '',
      user2: json['user2'] as String? ?? '',
      startedAt: json['startedAt'] as int? ?? 0,
      endedAt: json['endedAt'] as int?,
      status: json['status'] as String? ?? 'waiting',
      initiator: json['initiator'] as String? ?? '',
      user1Name: json['user1Name'] as String?,
      user2Name: json['user2Name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user1': user1,
      'user2': user2,
      'startedAt': startedAt,
      'endedAt': endedAt,
      'status': status,
      'initiator': initiator,
      'user1Name': user1Name,
      'user2Name': user2Name,
    };
  }

  /// Get the partner's UID given the current user's UID.
  String getPartnerUid(String myUid) {
    return myUid == user1 ? user2 : user1;
  }

  /// Get the partner's name given the current user's UID.
  String? getPartnerName(String myUid) {
    return myUid == user1 ? user2Name : user1Name;
  }

  @override
  List<Object?> get props => [matchId, user1, user2, status];
}
