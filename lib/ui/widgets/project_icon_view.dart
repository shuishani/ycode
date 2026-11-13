import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../models/project_icon.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'lucide_icon.dart';
import 'mobile_widgets.dart';

/// A project's icon as a tile the size of every list avatar, with a folder
/// badge so a project never reads as a conversation: its picture, emoji or
/// glyph on a soft square, or else its own name's initial in its tone on a
/// tint of it (a conversation's is white on the solid tone).
/// Image ids are fetched once through [IconCache].
class ProjectIconView extends StatelessWidget {
  const ProjectIconView({
    super.key,
    required this.state,
    required this.ref,
    this.size = MobileSizes.avatar,
    this.showBadge = true,
  });

  final AppState state;
  final ProjectRef ref;
  final double size;

  /// 文件夹角标；侧边栏的小图标在项目分组的标题上，用不着它。
  final bool showBadge;

  static const _muted = Color(0xFF91A8AF);

  @override
  Widget build(BuildContext context) {
    Widget tile(Widget child, {Color? tint}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (tint ?? _muted).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(size * MobileSizes.avatarCorner),
      ),
      child: child,
    );
    // 首字用它的色调写在同色的浅底上；对话是实心色块白字，两种一眼分得开。
    Widget letter(String name) {
      final tone = letterToneOf(name);
      return tile(
        Text(
          name.isEmpty ? '?' : String.fromCharCode(name.runes.first),
          style: TextStyle(
            color: tone,
            fontSize: size * .48,
            fontWeight: FontWeight.w600,
          ),
        ),
        tint: tone,
      );
    }

    final initial = letter(ref.project.name);
    final icon = switch (ProjectIcon.parse(ref.project.icon)) {
      null => initial,
      ProjectBrandIcon(:final name) => letter(name),
      ProjectEmojiIcon(:final emoji) => tile(
        SizedBox.square(
          dimension: size * .56,
          child: FittedBox(child: Text(emoji)),
        ),
      ),
      ProjectCodiconIcon(:final name, :final color) => tile(
        Icon(
          _codiconGlyph(name),
          size: size * .56,
          color: _themeColor(color) ?? _muted,
        ),
        tint: _themeColor(color),
      ),
      ProjectImageIcon(:final id) => FutureBuilder<Uint8List?>(
        future: state.icons.get(
          ref.desktopId,
          LinkMethods.icon,
          id,
          params: {'id': id},
          request: state.request,
        ),
        builder: (context, snapshot) => switch (snapshot.data) {
          null => initial,
          final bytes => ClipRRect(
            borderRadius: BorderRadius.circular(
              size * MobileSizes.avatarCorner,
            ),
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        },
      ),
    };
    if (!showBadge) return icon;
    // 右下角的文件夹角标：不管画的是什么，都看得出这是项目。右上角留给待办数。
    final scheme = Theme.of(context).colorScheme;
    final badge = size * .4;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          key: const ValueKey('project-folder-badge'),
          right: -badge * .2,
          bottom: -badge * .2,
          child: Container(
            width: badge,
            height: badge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 1.5),
            ),
            child: LucideIcon(
              'folder',
              size: badge * .6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static IconData _codiconGlyph(String name) => switch (name) {
    'folder' || 'folder-opened' || 'default_folder' => Icons.folder_outlined,
    'rocket' => Icons.rocket_launch_outlined,
    'beaker' || 'flame' => Icons.science_outlined,
    'book' => Icons.menu_book_outlined,
    'bug' => Icons.bug_report_outlined,
    'gear' || 'settings-gear' || 'gear-colored' => Icons.settings_outlined,
    'cloud' => Icons.cloud_outlined,
    'terminal' => Icons.terminal_outlined,
    'package' => Icons.inventory_2_outlined,
    'law' => Icons.gavel_outlined,
    'lightbulb' => Icons.lightbulb_outline,
    'paintcan' => Icons.palette_outlined,
    'server' || 'database' => Icons.dns_outlined,
    'globe' => Icons.public_outlined,
    'organization' => Icons.corporate_fare_outlined,
    _ => Icons.folder_outlined,
  };

  /// Theme color ids vary per desktop theme; accept plain color words and
  /// ignore anything unrecognized instead of guessing.
  static Color? _themeColor(String? id) {
    if (id == null) return null;
    final name = id.split('.').last.toLowerCase();
    return switch (name) {
      'blue' => const Color(0xFF4F7FC1),
      'green' => const Color(0xFF4E9A7A),
      'red' => const Color(0xFFC8625A),
      'orange' || 'yellow' => const Color(0xFFC17A45),
      'purple' => const Color(0xFF7F6DB8),
      'teal' || 'cyan' => const Color(0xFF4A98A8),
      _ => null,
    };
  }
}
