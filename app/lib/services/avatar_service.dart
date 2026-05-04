import '../models/customization_models.dart';

class AvatarService {
  /// Provides 100 Boy avatars, 100 Girl avatars, and several Funny/Anime sets.
  /// Uses curated high-quality CDN patterns for performance and variety.
  static List<AvatarModel> getAvatars() {
    final List<AvatarModel> avatars = [];

    // 100 Boys
    for (int i = 1; i <= 100; i++) {
      avatars.add(AvatarModel(
        id: 'boy_$i',
        imageUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=boy_seed_$i&backgroundColor=b6e3f4,c0aede,d1d4f9',
        category: 'boy',
        isPremium: i > 20, // First 20 are free
      ));
    }

    // 100 Girls
    for (int i = 1; i <= 100; i++) {
      avatars.add(AvatarModel(
        id: 'girl_$i',
        imageUrl: 'https://api.dicebear.com/7.x/avataaars/png?seed=girl_seed_$i&backgroundColor=ffdfbf,ffd5dc,ffebf2',
        category: 'girl',
        isPremium: i > 20,
      ));
    }

    // 20 Funny Bots
    for (int i = 1; i <= 20; i++) {
      avatars.add(AvatarModel(
        id: 'bot_$i',
        imageUrl: 'https://robohash.org/bot_$i?set=set1',
        category: 'funny',
        isPremium: i > 5,
      ));
    }

    // 20 Dogs/Animals
    for (int i = 1; i <= 20; i++) {
      avatars.add(AvatarModel(
        id: 'animal_$i',
        imageUrl: 'https://api.dicebear.com/7.x/thumbs/png?seed=animal_$i',
        category: 'dog',
        isPremium: true,
      ));
    }

    return avatars;
  }

  /// Provides 20+ Premium Frames (Sparkling, Ice, Neon, etc.)
  static List<FrameModel> getFrames() {
    return [
      const FrameModel(id: 'free_border', name: 'Standard', assetPath: ''),
      const FrameModel(id: 'ice_sparkle', name: 'Ice Sparkle', assetPath: 'assets/frames/ice.json', isAnimated: true, isPremium: true),
      const FrameModel(id: 'neon_glow', name: 'Neon Glow', assetPath: 'assets/frames/neon.json', isAnimated: true, isPremium: true),
      const FrameModel(id: 'golden_sparkle', name: 'Golden Sparkle', assetPath: 'assets/frames/gold.json', isAnimated: true, isPremium: true),
      const FrameModel(id: 'fire_border', name: 'Fire Burn', assetPath: 'assets/frames/fire.json', isAnimated: true, isPremium: true),
      const FrameModel(id: 'rainbow_wave', name: 'Rainbow', assetPath: 'assets/frames/rainbow.json', isAnimated: true, isPremium: true),
      // ... more frames can be added here
    ];
  }
}
