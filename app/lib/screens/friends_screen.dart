import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_colors.dart';
import '../config/app_typography.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/constants.dart';
import '../widgets/avatar_widget.dart';
import 'package:go_router/go_router.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final DatabaseService _db = DatabaseService();

  void _showProfileInfo(UserModel friend) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWidget(
              name: friend.name,
              avatarCode: friend.avatarUrl,
              radius: 40,
            ),
            const SizedBox(height: 16),
            Text(friend.name, style: AppTypography.headlineMedium),
            Text(friend.email, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _infoCard('Age', friend.age.isEmpty ? 'N/A' : friend.age, Icons.cake),
                _infoCard('Gender', friend.gender.isEmpty ? 'N/A' : friend.gender, Icons.person),
                _infoCard('Location', friend.country.isEmpty ? 'N/A' : friend.country, Icons.location_on),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.videocam_rounded, color: Colors.white),
                    label: const Text('Direct Call', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(context);
                      _startDirectCall(friend.uid);
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
          ],
        ),
      ),
    );
  }

  void _startDirectCall(String partnerUid) async {
    final myUid = context.read<AuthProvider>().firebaseUser!.uid;
    try {
      await FirebaseDatabase.instance.ref('direct_calls').child(partnerUid).set({
        'callerId': myUid,
        'callerName': context.read<AuthProvider>().userModel!.name,
        'timestamp': ServerValue.timestamp,
      });
      if (mounted) {
         context.push('/call');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to place call.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _infoCard(String title, String val, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 28),
        const SizedBox(height: 8),
        Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthProvider>().firebaseUser;
    if (authUser == null) return const SizedBox.shrink();

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref(AppConstants.usersPath).child(authUser.uid).onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final user = UserModel.fromJson(userData, authUser.uid);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          body: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  tabs: [
                    Tab(text: 'Friends (${user.friends.length})'),
                    Tab(text: 'Requests (${user.friendRequests.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildFriendsList(user, isDark),
                      _buildRequestsList(user, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showGlobalDiscovery(user),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.person_add_rounded, color: Colors.white),
            label: const Text('Add Friends', style: TextStyle(color: Colors.white)),
          ),
        );
      },
    );
  }

  void _showGlobalDiscovery(UserModel currentUser) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _DiscoveryModal(currentUser: currentUser);
      },
    );
  }

  Widget _buildFriendsList(UserModel user, bool isDark) {
    if (user.friends.isEmpty) {
      return const Center(child: Text('No friends yet. Add friends during an active call!'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: user.friends.length,
      itemBuilder: (context, index) {
        final friendUid = user.friends[index];
        // Stream each friend's online status instantly
        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref(AppConstants.usersPath).child(friendUid).onValue,
          builder: (context, snapshot) {
             if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
               return const SizedBox.shrink();
             }
             final friendData = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
             final friend = UserModel.fromJson(friendData, friendUid);

            return ListTile(
              onTap: () => _showProfileInfo(friend),
              leading: Stack(
                children: [
                  AvatarWidget(
                    name: friend.name,
                    avatarCode: friend.avatarUrl,
                    radius: 20,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: friend.isOnline ? AppColors.success : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, width: 2),
                      ),
                    ),
                  )
                ],
              ),
              title: Text(friend.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(friend.isOnline ? 'Online' : 'Offline', 
                style: TextStyle(color: friend.isOnline ? AppColors.success : AppColors.textSecondary, fontSize: 13)
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (val) {
                  if (val == 'remove') {
                    _db.removeFriend(user.uid, friend.uid);
                  } else if (val == 'block') {
                    _db.blockUser(user.uid, friend.uid);
                    _db.removeFriend(user.uid, friend.uid);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remove Friend', style: TextStyle(color: AppColors.error))),
                  PopupMenuItem(value: 'block', child: Text('Block User')),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsList(UserModel user, bool isDark) {
    if (user.friendRequests.isEmpty) {
      return const Center(child: Text('No pending requests.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: user.friendRequests.length,
      itemBuilder: (context, index) {
        final reqUid = user.friendRequests[index];
        return FutureBuilder<UserModel?>(
          future: _db.getUser(reqUid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final reqUser = snapshot.data!;
            return ListTile(
              onTap: () => _showProfileInfo(reqUser),
              leading: AvatarWidget(
                name: reqUser.name,
                avatarCode: reqUser.avatarUrl,
                radius: 20,
              ),
              title: Text(reqUser.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Sent you a friend request'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
                    onPressed: () => _db.acceptFriendRequest(user.uid, reqUser.uid),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_rounded, color: AppColors.error, size: 28),
                    onPressed: () => _db.rejectFriendRequest(user.uid, reqUser.uid),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DiscoveryModal extends StatefulWidget {
  final UserModel currentUser;
  const _DiscoveryModal({required this.currentUser});

  @override
  State<_DiscoveryModal> createState() => _DiscoveryModalState();
}

class _DiscoveryModalState extends State<_DiscoveryModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  final DatabaseService _db = DatabaseService();
  UserModel? _foundUser;
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _requestSent = false;

  void _onSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a 6-digit UID')),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _foundUser = null;
      _requestSent = false;
    });

    final user = await _db.getUserByDisplayId(query);
    
    if (mounted) {
      setState(() {
        _isSearching = false;
        _foundUser = user;
        if (user != null) {
          _requestSent = user.friendRequests.contains(widget.currentUser.uid);
        }
      });
    }
  }

  void _sendRequest() async {
    if (_foundUser == null) return;
    
    setState(() => _isSearching = true);
    await _db.sendFriendRequest(widget.currentUser.uid, _foundUser!.uid);
    
    if (mounted) {
      setState(() {
        _isSearching = false;
        _requestSent = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7 + bottomInset,
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Find Friend', style: AppTypography.headlineMedium),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Enter the 6-digit numeric UID of your friend to connect.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          
          // Search Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    hintText: 'e.g. 123456',
                    counterText: '',
                    prefixIcon: const Icon(Icons.tag_rounded),
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isSearching ? null : _onSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSearching 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          
          // Result area
          Expanded(
            child: _hasSearched 
              ? (_foundUser != null 
                  ? _buildUserResult()
                  : const Center(child: Text('No user found with this UID.')))
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_search_rounded, size: 64, color: AppColors.primary.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      const Text('Search result will appear here'),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserResult() {
    final alreadyFriends = widget.currentUser.friends.contains(_foundUser!.uid);
    final isMe = _foundUser!.uid == widget.currentUser.uid;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              AvatarWidget(
                name: _foundUser!.name,
                avatarCode: _foundUser!.avatarUrl,
                radius: 35,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_foundUser!.name, style: AppTypography.headlineSmall.copyWith(fontSize: 20)),
                    const SizedBox(height: 4),
                     Text(_foundUser!.country.isNotEmpty ? _foundUser!.country : 'Zuumeet User', 
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        if (isMe)
          const Text('This is you!', style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary))
        else if (alreadyFriends)
          ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Already Friends'),
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: AppColors.success.withValues(alpha: 0.2),
              disabledForegroundColor: AppColors.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              minimumSize: const Size(double.infinity, 54),
            ),
          )
        else if (_requestSent)
          _buildAnimatedSuccess()
        else
          ElevatedButton.icon(
            onPressed: _sendRequest,
            icon: const Icon(Icons.person_add_rounded, color: Colors.white),
            label: const Text('Send Friend Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              minimumSize: const Size(double.infinity, 54),
            ),
          ),
      ],
    );
  }

  Widget _buildAnimatedSuccess() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 12),
                Text('Request Sent!', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
        );
      },
    );
  }
}
