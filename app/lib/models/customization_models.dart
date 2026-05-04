import 'package:equatable/equatable.dart';

class AvatarModel extends Equatable {
  final String id;
  final String imageUrl;
  final String category; // 'boy', 'girl', 'funny', 'dog', 'anime'
  final bool isPremium;

  const AvatarModel({
    required this.id,
    required this.imageUrl,
    required this.category,
    this.isPremium = false,
  });

  @override
  List<Object?> get props => [id, imageUrl, category, isPremium];
}

class FrameModel extends Equatable {
  final String id;
  final String name;
  final String assetPath; // Or Lottie path for animated frames
  final bool isAnimated;
  final bool isPremium;

  const FrameModel({
    required this.id,
    required this.name,
    required this.assetPath,
    this.isAnimated = false,
    this.isPremium = false,
  });

  @override
  List<Object?> get props => [id, name, assetPath, isAnimated, isPremium];
}
