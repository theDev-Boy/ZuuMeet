import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../config/app_dimensions.dart';
import '../config/app_typography.dart';
import '../models/match_model.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../widgets/avatar_widget.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _db = DatabaseService();
  List<MatchModel>? _history;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final uid = context.read<AuthProvider>().firebaseUser?.uid;
    if (uid != null) {
      final history = await _db.getCallHistory(uid);
      if (mounted) {
        setState(() {
          _history = history;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_history == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_history!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history_toggle_off, size: 80, color: AppColors.textLight),
            const SizedBox(height: 16),
            Text('No calls yet', style: AppTypography.headlineSmall.copyWith(color: AppColors.textLight)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history!.length,
      itemBuilder: (context, index) {
        final match = _history![index];
        final partnerName = match.getPartnerName(context.read<AuthProvider>().firebaseUser!.uid) ?? 'Anonymous';
        final date = DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(match.startedAt));
        
        String duration = 'Short session';
        if (match.endedAt != null) {
          final diff = match.endedAt! - match.startedAt;
          final min = diff ~/ 60000;
          final sec = (diff % 60000) ~/ 1000;
          duration = '${min}m ${sec}s';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusM)),
          elevation: 0,
          color: AppColors.backgroundSecondary,
          child: ListTile(
            onLongPress: () => _confirmDelete(match),
            leading: AvatarWidget(
              name: partnerName,
              avatarCode: '', // In a real app we'd fetch this from the partnerId cache
              radius: 20,
            ),
            title: Text(partnerName, style: AppTypography.button),
            subtitle: Text('$date\n$duration', style: AppTypography.caption),
            isThreeLine: true,
            trailing: const Icon(Icons.video_call, color: AppColors.primary),
          ),
        );
      },
    );
  }
  void _confirmDelete(MatchModel match) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete History?'),
        content: const Text('Do you want to remove this call from your history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              // Delete logic here
              Navigator.pop(context);
            }, 
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
