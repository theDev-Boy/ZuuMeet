import 'package:equatable/equatable.dart';

/// Represents a user report.
class ReportModel extends Equatable {
  final String reportId;
  final String reporter;
  final String reported;
  final String reason;
  final int timestamp;
  final String status; // 'pending', 'reviewed', 'actioned'

  const ReportModel({
    required this.reportId,
    required this.reporter,
    required this.reported,
    required this.reason,
    required this.timestamp,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() {
    return {
      'reporter': reporter,
      'reported': reported,
      'reason': reason,
      'timestamp': timestamp,
      'status': status,
    };
  }

  factory ReportModel.fromJson(Map<dynamic, dynamic> json, String reportId) {
    return ReportModel(
      reportId: reportId,
      reporter: json['reporter'] as String? ?? '',
      reported: json['reported'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
    );
  }

  @override
  List<Object?> get props => [reportId, reporter, reported];
}
