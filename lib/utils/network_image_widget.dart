import 'package:cached_network_image/cached_network_image.dart';
import 'package:driver/utils/app_image_cache.dart';
import 'package:driver/constant/constant.dart';
import 'package:driver/themes/responsive.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class NetworkImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final Widget? errorWidget;
  final BoxFit? fit;
  final double? borderRadius;
  final Color? color;

  final bool showShimmer;

  const NetworkImageWidget({
    super.key,
    this.height,
    this.width,
    this.fit,
    required this.imageUrl,
    this.borderRadius,
    this.errorWidget,
    this.color,
    this.showShimmer = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = width ?? Responsive.width(15, context);
    final h = height ?? Responsive.height(8, context);
    // Decode at the size actually drawn, not at the size uploaded.
    //
    // These photographs come off the admin panel at up to 1152 px wide, and
    // Flutter decodes every one of them to full-size ARGB in memory — several
    // megabytes each — however small the box on screen is. A list of them
    // thrashes the 100 MB image cache and drops frames while scrolling. This
    // changes nothing about which image is shown or how sharp it looks: the
    // ceiling is the pixel width of the widget on this device.
    final int decodeWidth = (w * MediaQuery.devicePixelRatioOf(context)).round();

    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: AppImageCache.manager,
      memCacheWidth: decodeWidth,
      fit: fit ?? BoxFit.fitWidth,
      height: h,
      width: w,
      color: color,
      placeholder:
          (context, url) =>
              showShimmer
                  ? Shimmer.fromColors(
                    baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
                    highlightColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5),
                    child: Container(height: h, width: w, color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0)),
                  )
                  : SizedBox(height: h, width: w),
      errorWidget: (context, url, error) => errorWidget ?? CachedNetworkImage(imageUrl: Constant.placeHolderImage, cacheManager: AppImageCache.manager, memCacheWidth: decodeWidth, fit: fit ?? BoxFit.fitWidth, height: h, width: w),
    );
  }
}
