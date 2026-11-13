import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../markdown/finite_selection_edges.dart';
import 'shimmer_text.dart';
import '../../theme/app_theme.dart';

/// Header of a step the agent took, e.g. "Ran  Check the Flutter version":
/// what it did, then what on, muted. While it is [running] the whole line
/// shimmers. With [onToggle] it opens and closes on a tap; a chevron always
/// shows. With [onOpen] a tap opens its file instead, and the chevron
/// becomes the one that opens and closes it.
///
/// Mobile adaptation of the desktop header: no hover (the chevron is always
/// visible), no wheel latch or smooth scroll (touch scrolling needs neither),
/// and the click arbitrates with the selection's long-press by duration.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.verb,
    this.object = '',
    this.detail,
    this.running = false,
    this.expanded = false,
    this.onToggle,
    this.onOpen,
    this.openTooltip,
    this.icon,
    this.trailing,
    this.trailingGap = 6,
    this.action,
    this.spans,
    this.bold = false,
  });

  final String verb;
  final String object;

  /// A last word, fainter still (e.g. "L1-40", "+12 -3").
  final String? detail;
  final bool running;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Opens the file it is about: its click, unless it opens to more
  /// ([onToggle]).
  final VoidCallback? onOpen;

  /// What [onOpen] does, for assistive technologies.
  final String? openTooltip;

  /// Before the line, e.g. a message's arrows.
  final Widget? icon;

  /// After the line, e.g. an edit's "+12 -3".
  final Widget? trailing;

  /// 文字与 [trailing] 之间的间距；尾部组件自带间距时可设为零。
  final double trailingGap;

  /// A button after it all, apart from the click that opens it.
  final Widget? action;

  /// The line in parts, in place of [verb], [object] and [detail]: e.g. a
  /// fold's counts, standing out of its words.
  final List<InlineSpan>? spans;

  /// The line in bold, as a title (a summarized thought's, say).
  final bool bold;

  /// Its text's size, as steps read.
  static const fontSize = MobileType.secondary;

  /// The line as text, e.g. for copying.
  static String text(String verb, String object, [String? detail]) =>
      [verb, object, ?detail].where((part) => part.isNotEmpty).join(' ');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final toggle = onToggle;
    final weight = bold ? FontWeight.w600 : null;
    final faint = scheme.onSurfaceVariant.withValues(
      alpha: MobileTheme.asideAlpha,
    );
    final line = spans != null
        ? Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: fontSize,
            ),
          )
        : running
        ? ShimmerText(
            text(verb, object, detail),
            ellipsis: false,
            padding: EdgeInsets.zero,
            style: TextStyle(fontWeight: weight),
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: verb,
                  style: TextStyle(color: scheme.onSurface),
                ),
                if (object.isNotEmpty)
                  TextSpan(text: verb.isEmpty ? object : ' $object'),
                if (detail case final detail? when detail.isNotEmpty)
                  TextSpan(
                    text: ' $detail',
                    style: TextStyle(color: faint),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: fontSize,
              fontWeight: weight,
            ),
          );
    // One that opens to more toggles on its click; one that opens a file
    // does that on its click, its chevron toggling instead.
    final open = toggle == null ? onOpen : null;
    final click = open ?? toggle;
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            SelectionContainer.disabled(child: icon),
            const SizedBox(width: 5),
          ],
          // Shrinks in a narrow window rather than overflow.
          Flexible(child: line),
          if (trailing case final trailing?) ...[
            SizedBox(width: trailingGap),
            trailing,
          ],
          if (open != null) ...[
            const SizedBox(width: 2),
            SelectionContainer.disabled(
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: scheme.onSurface,
              ),
            ),
          ],
          if (toggle != null) ...[
            const SizedBox(width: 2),
            // Kept out of the selection, which would otherwise re-resolve
            // its edges each time it changes.
            SelectionContainer.disabled(child: _chevron(scheme)),
          ],
        ],
      ),
    );
    Widget clickable = click == null
        ? header
        : _ClickListener(onClick: click, child: header);
    if (open != null) {
      clickable = Semantics(button: true, label: openTooltip, child: clickable);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: clickable),
        if (action case final action?) ...[const SizedBox(width: 10), action],
      ],
    );
  }

  Widget _chevron(ColorScheme scheme) => AnimatedRotation(
    turns: expanded ? 0.25 : 0,
    duration: const Duration(milliseconds: 150),
    child: Icon(
      Icons.chevron_right_rounded,
      size: 16,
      color: scheme.onSurfaceVariant,
    ),
  );
}

/// Calls [onClick] on a plain tap: not a drag, not a long-press (which the
/// selection uses). Listens rather than joins the gesture arena, so
/// selecting the text still works.
class _ClickListener extends StatefulWidget {
  const _ClickListener({required this.onClick, required this.child});

  final VoidCallback onClick;
  final Widget child;

  @override
  State<_ClickListener> createState() => _ClickListenerState();
}

class _ClickListenerState extends State<_ClickListener> {
  static const _moveSlop = 4.0;

  /// A hold this long is the selection's long-press, not a tap.
  static const _tapBudget = Duration(milliseconds: 300);

  Offset? _down;
  DateTime? _downAt;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton) {
          _down = event.position;
          _downAt = DateTime.now();
        } else {
          _down = null;
          _downAt = null;
        }
      },
      onPointerMove: (event) {
        final down = _down;
        if (down != null && (event.position - down).distance > _moveSlop) {
          _down = null;
        }
      },
      onPointerUp: (_) {
        final down = _down;
        final at = _downAt;
        _down = null;
        _downAt = null;
        if (down == null || at == null) return;
        if (DateTime.now().difference(at) >= _tapBudget) return;
        widget.onClick();
      },
      onPointerCancel: (_) {
        _down = null;
        _downAt = null;
      },
      child: widget.child,
    );
  }
}

/// What a step opens to: a framed box under its header, scrolling past
/// [maxHeight].
class StepBody extends StatefulWidget {
  const StepBody({
    super.key,
    required this.child,
    this.maxHeight = 240,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.followEnd = false,
    this.overlay,
    this.header,
  });

  final Widget child;
  final double maxHeight;
  final EdgeInsetsGeometry padding;

  /// Shows the end rather than the start while it grows (live output).
  final bool followEnd;

  /// Over its top right corner, e.g. a menu button.
  final Widget? overlay;

  /// Above [child], a line under it, staying while [child] scrolls.
  final Widget? header;

  @override
  State<StepBody> createState() => _StepBodyState();
}

class _StepBodyState extends State<StepBody> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(StepBody old) {
    super.didUpdateWidget(old);
    if (old.followEnd != widget.followEnd && _controller.hasClients) {
      _keepInView(_controller.position);
    }
  }

  /// [StepBody.followEnd] turns the view round (the command ended, or went
  /// to the background), its offset now counted from the other end: what
  /// was in view stays, rather than the view jumping to the far end.
  void _keepInView(ScrollPosition position) {
    // How far it is from the end its offset counted from, which is now the
    // far end.
    final held = position.pixels - position.minScrollExtent;
    // Before this frame's layout, so the far end never shows.
    position.correctPixels(position.maxScrollExtent - held);
    // At that end (following the output), it stays there, though the
    // output grew as it ended; scrolled off it, nothing in view moves.
    if (held > 0.5) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final now = _controller.position;
      if (now.pixels != now.maxScrollExtent) now.jumpTo(now.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final StepBody(:child, :maxHeight, :padding, :overlay, :header) = widget;
    Widget body = Stack(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            controller: _controller,
            reverse: widget.followEnd,
            padding: padding,
            child: FiniteSelectionEdges(
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ),
        if (overlay case final overlay?)
          Positioned(top: 6, right: 6, child: overlay),
      ],
    );
    if (header case final header?) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          body,
        ],
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

/// Monospaced text as steps show it: commands, output, matches.
TextStyle stepMono(BuildContext context) => TextStyle(
  fontFamily: 'monospace',
  fontSize: MobileType.mono,
  height: 1.5,
  color: Theme.of(context).colorScheme.onSurfaceVariant,
);
