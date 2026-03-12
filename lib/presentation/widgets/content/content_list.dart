import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/presentation/widgets/content/poster_card.dart';
import 'package:lifeostv/utils/responsive.dart';

class ContentList extends StatelessWidget {
  final String title;
  final List<Channel> channels;
  final Function(Channel) onChannelTap;
  final Function(Channel)? onChannelFocus;
  final IconData? icon;
  final Widget? trailing;

  const ContentList({
    super.key,
    required this.title,
    required this.channels,
    required this.onChannelTap,
    this.onChannelFocus,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    final hPad = context.horizontalPadding;
    final isMobile = context.isMobileWidth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: isMobile ? 8 : 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: isMobile ? 16 : 20,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${channels.length}',
                style: TextStyle(
                  color: AppColors.textTertiaryDark,
                  fontWeight: FontWeight.w500,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
        ),
        SizedBox(
          height: context.carouselHeight,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
            ),
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              scrollDirection: Axis.horizontal,
              itemCount: channels.length,
              separatorBuilder: (_, __) => SizedBox(width: isMobile ? 8 : 12),
              itemBuilder: (context, index) {
                return Center(
                  child: PosterCard(
                    channel: channels[index],
                    width: context.posterWidth,
                    height: context.posterHeight,
                    onTap: () => onChannelTap(channels[index]),
                    onFocus: () => onChannelFocus?.call(channels[index]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
