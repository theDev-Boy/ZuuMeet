import 'dart:math';

class AvatarGenerator {
  static const List<String> animeGirls = [
    'https://api.dicebear.com/7.x/avataaars/svg?seed=Girl1&clothing=shirt&hair=long',
    'https://api.dicebear.com/7.x/avataaars/svg?seed=Girl2&clothing=overall&hair=bob',
  ];

  static const List<String> animeBoys = [
    'https://api.dicebear.com/7.x/avataaars/svg?seed=Boy1&clothing=hoodie&hair=short',
    'https://api.dicebear.com/7.x/avataaars/svg?seed=Boy2&clothing=shirt&hair=mohawk',
  ];

  static const List<String> emojis = ['😎', '🤖', '👻', '🐱', '🐶', '🦊', '🦄', '🌈', '🍦', '🍕'];

  /// Since the user wants 'coded not real pic', I'll use DiceBear API seeds for Anime 
  /// or Emojis which are essentially coded SVGs.
  
  static String getRandomAnime(bool isGirl) {
    final seed = Random().nextInt(10000).toString();
    final type = isGirl ? 'avataaars' : 'micah';
    return 'dicebear:$type:$seed';
  }

  static String getRandomEmoji() {
    return 'emoji:${emojis[Random().nextInt(emojis.length)]}';
  }
}
