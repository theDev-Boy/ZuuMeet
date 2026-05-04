import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../providers/auth_provider.dart';
import '../widgets/avatar_widget.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().firebaseUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.error),
            onPressed: () => _confirmClearAll(uid),
            tooltip: 'Clear All',
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('call_history').child(uid).onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return _buildEmptyState();
          }

          final data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
          final history = data.entries.map((e) {
            final val = Map<dynamic, dynamic>.from(e.value as Map);
            return {
              'id': e.key as String,
              'partnerName': val['partnerName'] ?? 'Anonymous',
              'timestamp': val['timestamp'] ?? 0,
              'durationSeconds': val['durationSeconds'] ?? 0,
              'type': val['type'] ?? 'video',
            };
          }).toList();

          // Sort by timestamp descending
          history.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              final date = DateFormat.yMMMd().add_jm().format(
                DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int),
              );
              
              final durSec = item['durationSeconds'] as int;
              final min = durSec ~/ 60;
              final sec = durSec % 60;
              final duration = '${min}m ${sec}s';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withValues(alpha: 0.05) 
                    : Colors.grey[100],
                child: ListTile(
                  leading: AvatarWidget(
                    name: item['partnerName'] as String,
                    avatarCode: '', 
                    radius: 20,
                  ),
                  title: Text(item['partnerName'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('$date • $duration', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary, size: 20),
                    onPressed: () => _deleteItem(uid, item['id'] as String),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 80, color: AppColors.primary.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('No call history yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
        ],
      ),
    );
  }

  void _deleteItem(String uid, String id) {
    FirebaseDatabase.instance.ref('call_history').child(uid).child(id).remove();
  }

  void _confirmClearAll(String uid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All History?'),
        content: const Text('This will permanently delete all your call records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              FirebaseDatabase.instance.ref('call_history').child(uid).remove();
              Navigator.pop(context);
            }, 
            child: const Text('Clear All', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
