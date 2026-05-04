import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_colors.dart';
import '../config/app_typography.dart';
import '../models/customization_models.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import '../services/avatar_service.dart';
import '../widgets/avatar_widget.dart';

class CustomAvatarScreen extends StatefulWidget {
  const CustomAvatarScreen({super.key});

  @override
  State<CustomAvatarScreen> createState() => _CustomAvatarScreenState();
}

class _CustomAvatarScreenState extends State<CustomAvatarScreen> {
  String _selectedCategory = 'boy';
  String? _tempAvatarUrl;
  String? _tempFrameId;
  
  late List<AvatarModel> _allAvatars;
  late List<FrameModel> _allFrames;

  @override
  void initState() {
    super.initState();
    _allAvatars = AvatarService.getAvatars();
    _allFrames = AvatarService.getFrames();
    
    final user = context.read<AuthProvider>().userModel;
    if (user != null) {
      _tempAvatarUrl = user.avatarUrl;
      _tempFrameId = user.frameId;
    }
  }

  void _onCategoryChanged(String category) {
    setState(() => _selectedCategory = category);
  }

  void _onSelectAvatar(AvatarModel avatar) {
    setState(() => _tempAvatarUrl = avatar.imageUrl);
    if (avatar.isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium Avatar Selected'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _onSelectFrame(FrameModel frame) {
    if (frame.isPremium) {
      setState(() => _tempFrameId = frame.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium Frame Selected'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() => _tempFrameId = frame.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().userModel;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Create a preview user model
    final previewUser = user.copyWith(
      avatarUrl: _tempAvatarUrl ?? user.avatarUrl,
      frameId: _tempFrameId ?? user.frameId,
    );

    final filteredAvatars = _allAvatars.where((a) => a.category == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize Profile'),
        actions: [
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await context.read<UserProvider>().updateAvatarAndFrame(
                user.uid, 
                _tempAvatarUrl ?? '', 
                _tempFrameId ?? 'free_border'
              );
              nav.pop();
            },
            child: const Text('SAVE', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // PREVIEW SECTION
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary.withValues(alpha: 0.1), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                AvatarWidget(user: previewUser, radius: 60),
                const SizedBox(height: 16),
                Text(user.name, style: AppTypography.headlineMedium),
                const SizedBox(height: 4),
                Text('Preview Mode', style: AppTypography.caption),
              ],
            ),
          ),

          // CATEGORIES
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['boy', 'girl', 'funny', 'dog', 'anime'].map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat.toUpperCase()),
                    selected: isSelected,
                    onSelected: (_) => _onCategoryChanged(cat),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : AppColors.textSecondary),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),

          // SELECTION TABS
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                   const TabBar(
                     indicatorColor: AppColors.primary,
                     labelColor: AppColors.primary,
                     tabs: [Tab(text: 'AVATARS'), Tab(text: 'FRAMES')],
                   ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // AVATAR GRID
                        GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: filteredAvatars.length,
                          itemBuilder: (context, index) {
                            final avatar = filteredAvatars[index];
                            final isSelected = _tempAvatarUrl == avatar.imageUrl;

                            return GestureDetector(
                              onTap: () => _onSelectAvatar(avatar),
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? AppColors.primary : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(imageUrl: avatar.imageUrl),
                                    ),
                                  ),
                                  if (avatar.isPremium)
                                    const Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Icon(Icons.lock_rounded, size: 14, color: Colors.amber),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),

                        // FRAME GRID
                        GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                          itemCount: _allFrames.length,
                          itemBuilder: (context, index) {
                            final frame = _allFrames[index];
                            final isSelected = _tempFrameId == frame.id;

                            return GestureDetector(
                              onTap: () => _onSelectFrame(frame),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundSecondary,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AvatarWidget(
                                      user: user.copyWith(frameId: frame.id), 
                                      radius: 30,
                                    ),
                                    if (frame.isPremium)
                                      const Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Icon(Icons.lock_rounded, size: 16, color: Colors.amber),
                                      ),
                                    Positioned(
                                      bottom: 4,
                                      child: Text(frame.name, style: const TextStyle(fontSize: 10)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
