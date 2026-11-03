import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 圆角封面图，带加载占位与失败占位
class CoverImage extends StatelessWidget {
  final String url;
  final double size;
  final double radius;

  const CoverImage({
    super.key,
    required this.url,
    this.size = 48,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHigh,
      child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => Stack(
                  children: [
                    Positioned.fill(child: placeholder),
                    const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ),
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}
