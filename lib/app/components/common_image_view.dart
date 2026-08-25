import 'dart:io';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_images.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CommonImageView extends StatelessWidget {
  ///[url] is required parameter for fetching network image
  final String? url;

  ///[imagePath] is required parameter for showing png,jpg,etc image
  final String? imagePath;

  ///[svgPath] is required parameter for showing svg image
  final String? svgPath;

  ///[file] is required parameter for fetching image file
  final File? file;

  final double? height;
  final double? width;
  final Color? color;
  final BoxFit fit;
  final String placeHolder;
  final Alignment? alignment;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry radius;
  final BoxBorder? border;
  final bool matchTextDirection;

  ///a [CustomImageView] it can be used for showing any type of images
  /// it will shows the placeholder image if image is not found on network image
  const CommonImageView({
    super.key,
    this.url,
    this.imagePath,
    this.svgPath,
    this.file,
    this.height,
    this.width,
    this.color,
    this.fit = BoxFit.fill,
    this.alignment,
    this.onTap,
    this.radius = BorderRadius.zero,
    this.margin,
    this.border,
    this.placeHolder = AppImages.placeHolderImage,
    this.matchTextDirection = false,
  });

  @override
  Widget build(BuildContext context) {
    return alignment != null
        ? Align(alignment: alignment!, child: _buildWidget())
        : _buildWidget();
  }

  Widget _buildWidget() {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: GestureDetector(onTap: onTap, child: _buildCircleImage()),
    );
  }

  ///build the image with border radius
  _buildCircleImage() {
    return ClipRRect(borderRadius: radius, child: _buildImageWithBorder());
  }

  ///build the image with border and border radius style
  _buildImageWithBorder() {
    if (border != null) {
      return Container(
        decoration: BoxDecoration(border: border, borderRadius: radius),
        child: _buildImageView(),
      );
    } else {
      return _buildImageView();
    }
  }

  /// Build error/placeholder widget
  Widget _buildPlaceholder() {
    // Try to check if placeholder is SVG and valid
    if (placeHolder.endsWith('.svg')) {
      try {
        return SvgPicture.asset(
          placeHolder,
          // color: AppColors.gray600.withOpacity(0.5),
          height: height,
          width: width,
          fit: fit,
          matchTextDirection: matchTextDirection,
        );
      } catch (e) {
        // If SVG fails, fall back to icon
        return _buildFallbackIcon();
      }
    } else {
      // Try to load as regular image
      try {
        return Image.asset(
          placeHolder,
          // color: AppColors.gray600.withOpacity(0.5),
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return _buildFallbackIcon();
          },
        );
      } catch (e) {
        return _buildFallbackIcon();
      }
    }
  }

  /// Build fallback icon when everything else fails
  Widget _buildFallbackIcon() {
    return Container(
      height: height,
      width: width,
      color: AppColors.background,
      child: SvgIcon(
        assetName: AppImages.placeHolderImage,
        size: (height ?? 50) * 0.4,
      ),
    );
  }

  Widget _buildImageView() {
    if (file != null && file!.path.isNotEmpty) {
      return Image.file(
        file!,
        height: height,
        width: width,
        fit: fit,
        color: color,
        errorBuilder: (context, _, e) => _buildPlaceholder(),
      );
    } else if (url != null && url!.isNotEmpty) {
      return CachedNetworkImage(
        height: height,
        width: width,
        fit: fit,
        imageUrl: url!,
        color: color,
        placeholder: (context, url) => Container(
          height: height,
          width: width,
          color: AppColors.greySwatch200,
          child: Center(
            child: SizedBox(
              height: 30,
              width: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.greySwatch400,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    } else if (svgPath != null && svgPath!.isNotEmpty) {
      return SizedBox(
        height: height,
        width: width,
        child: SvgPicture.asset(
          svgPath!,
          height: height,
          width: width,
          fit: fit,
          color: color,
          matchTextDirection: matchTextDirection,
          placeholderBuilder: (context) => _buildFallbackIcon(),
        ),
      );
    } else if (imagePath != null && imagePath!.isNotEmpty) {
      // Lets a tenant-configured logo URL (see AppImages.logoImage /
      // BrandingService) flow through every existing `imagePath:` call site
      // unchanged, instead of needing a separate `url:` param everywhere.
      if (imagePath!.startsWith('http://') || imagePath!.startsWith('https://')) {
        return CachedNetworkImage(
          height: height,
          width: width,
          fit: fit,
          imageUrl: imagePath!,
          color: color,
          placeholder: (context, url) => _buildPlaceholder(),
          errorWidget: (context, url, error) => _buildPlaceholder(),
        );
      }
      return Image.asset(
        imagePath!,
        height: height,
        width: width,
        fit: fit,
        color: color,
        matchTextDirection: matchTextDirection,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
    return _buildFallbackIcon();
  }
}
