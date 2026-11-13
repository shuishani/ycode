import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../chat_models.dart';
import '../markdown/markdown_view.dart';
import '../markdown/safe_selection_indexes.dart';
import 'fade_curve.dart';
import 'strings.dart';
import '../../theme/app_theme.dart';
import '../../state/app_state.dart';

/// A plan's strings, both languages inline (see [ToolStrings]).
class PlanStrings {
  const PlanStrings._(this.zh);

  factory PlanStrings(bool zh) => zh ? zhCN : en;

  factory PlanStrings.standard() => PlanStrings(localeIsZh);

  static const zhCN = PlanStrings._(true);
  static const en = PlanStrings._(false);

  final bool zh;

  String status(PlanStatus status) => switch (status) {
    PlanStatus.drafting => zh ? '起草中' : 'drafting',
    PlanStatus.awaiting => zh ? '待开始' : 'awaiting approval',
    PlanStatus.approved => zh ? '已批准' : 'approved',
    PlanStatus.sentBack => zh ? '已退回' : 'sent back',
    PlanStatus.expired => zh ? '已失效' : 'no longer pending',
  };

  String get label => zh ? '计划' : 'Plan';
  String round(int round) => 'v$round';
}

/// A round of planning in the conversation: the plan's title over its
/// text, the text fading out past a height; a tap shows it in full —
/// on mobile, from the recorded text, or [onOpen] when only a file is known. A plan
/// sent back gives way to the next round's: it folds to one line, with
/// what the user said should change. The desktop's start-here bar
/// ([PlanStartBar]) stays a desktop affordance.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.item, this.onOpen, this.strings});

  final PlanItem item;

  /// Opens the plan's file whole; null, it cannot.
  final VoidCallback? onOpen;
  final PlanStrings? strings;

  /// The card as text, e.g. for copying.
  static String plainText(PlanItem item, {PlanStrings? strings}) {
    final s = strings ?? PlanStrings.standard();
    return [
      '${s.label} ${s.round(item.round)}',
      item.title ?? '',
      s.status(item.status),
      ?item.feedback,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // 先展示对话中已有的正文，原文件可能已删除或不在项目目录内。
    final text = item.text;
    final VoidCallback? open = text != null && text.trim().isNotEmpty
        ? () => _showRecorded(context, text)
        : item.path.isEmpty
        ? null
        : onOpen;
    final card = item.status == PlanStatus.sentBack
        ? _folded(context, open)
        : _card(context, open);
    return SizedBox(width: double.infinity, child: card);
  }

  void _showRecorded(BuildContext context, String text) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: AppState.phrase('关闭', 'Close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppState.phrase(
                    '显示对话中记录的版本，可能不是电脑文件的最新内容。',
                    'Showing the version recorded in this conversation, which may differ from the current file on the desktop.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: SelectionArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [MarkdownView(text)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sent back: one line.
  Widget _folded(BuildContext context, VoidCallback? open) {
    final s = strings ?? PlanStrings.standard();
    final scheme = Theme.of(context).colorScheme;
    final faint = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: MobileType.secondary,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text:
                          '${s.label} '
                          '${s.round(item.round)} · '
                          '${s.status(item.status)}',
                    ),
                    if (item.feedback case final feedback?)
                      TextSpan(text: '：$feedback'),
                  ],
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: faint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How high the card's text goes, past which it fades out: about twice
  /// a card without it.
  static const maxBodyHeight = 150.0;

  Widget _card(BuildContext context, VoidCallback? open) {
    final scheme = Theme.of(context).colorScheme;
    final text = _body(item);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: _content(context, text),
          ),
        ],
      ),
    );
  }

  /// The title, and the text under it.
  Widget _content(BuildContext context, String? text) {
    final s = strings ?? PlanStrings.standard();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // As the approvals that carry it out unasked show.
            Icon(Icons.checklist_rounded, size: 16, color: MobileAmber.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: MobileType.body,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            if (item.round > 1) ...[
              const SizedBox(width: 8),
              Text(
                s.round(item.round),
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(
                    alpha: MobileTheme.asideAlpha,
                  ),
                  fontSize: MobileType.aside,
                ),
              ),
            ],
          ],
        ),
        if (text != null) ...[
          const SizedBox(height: 6),
          // Its text is the card's: a tap on it opens the plan.
          IgnorePointer(child: _PlanPreview(text)),
        ],
      ],
    );
  }

  /// [item]'s text under its title: without the heading the title is.
  static String? _body(PlanItem item) {
    final text = item.text;
    if (text == null) return null;
    final lines = text.trimLeft().split('\n');
    if (lines.isNotEmpty && PlanItem.titleOf(lines.first) == item.title) {
      lines.removeAt(0);
    }
    final body = lines.join('\n').trim();
    return body.isEmpty ? null : body;
  }
}

/// The plan icon's amber, where the desktop reads the theme's caution
/// color: the mobile accent stands in.
class MobileAmber {
  static const color = Color(0xFF966A25);
}

/// One selectable bounded by the preview, not by the hidden plan below it.
class _PlanPreview extends StatefulWidget {
  const _PlanPreview(this.text);

  final String text;

  @override
  State<_PlanPreview> createState() => _PlanPreviewState();
}

class _PlanPreviewState extends State<_PlanPreview> {
  final _selection = _PlanPreviewSelectionDelegate();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionContainer(
    delegate: _selection,
    child: _FadedBody(
      maxHeight: PlanCard.maxBodyHeight,
      child: MarkdownView(
        widget.text,
        style: MarkdownView.baseStyle.copyWith(fontSize: MobileType.body),
      ),
    ),
  );
}

/// A paint clip does not clip selection events. Hidden paragraphs must not
/// receive a pointer meant for a later reply. Crossing the whole preview
/// still selects its full text, as select-all does.
class _PlanPreviewSelectionDelegate extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {
  SelectionResult _resultAt(Offset globalPosition) {
    final inverse = getTransformTo(null)..invert();
    return SelectionUtils.getResultBasedOnRect(
      Offset.zero & containerSize,
      MatrixUtils.transformPoint(inverse, globalPosition),
    );
  }

  Offset _outsideText(SelectionResult result) {
    var bounds = Offset.zero & containerSize;
    for (final selectable in selectables) {
      final transform = getTransformFrom(selectable);
      for (final rect in selectable.boundingBoxes) {
        bounds = bounds.expandToInclude(
          MatrixUtils.transformRect(transform, rect),
        );
      }
    }
    final local = result == SelectionResult.previous
        ? bounds.topLeft - const Offset(0, 1)
        : bounds.bottomRight + const Offset(0, 1);
    return MatrixUtils.transformPoint(getTransformTo(null), local);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event) {
      case SelectionEdgeUpdateEvent():
        final result = _resultAt(event.globalPosition);
        if (result == SelectionResult.end) {
          return super.dispatchSelectionEvent(event);
        }
        // Put the edge beyond all hidden text too, so a selection wholly
        // below the card clears it instead of leaving hidden words selected.
        final position = _outsideText(result);
        super.dispatchSelectionEvent(
          event.type == SelectionEventType.startEdgeUpdate
              ? SelectionEdgeUpdateEvent.forStart(
                  globalPosition: position,
                  granularity: event.granularity,
                )
              : SelectionEdgeUpdateEvent.forEnd(
                  globalPosition: position,
                  granularity: event.granularity,
                ),
        );
        return result;
      case SelectParagraphSelectionEvent(absorb: true):
        return super.dispatchSelectionEvent(event);
      case SelectWordSelectionEvent(:final globalPosition) ||
          SelectParagraphSelectionEvent(:final globalPosition):
        final result = _resultAt(globalPosition);
        if (result == SelectionResult.end) {
          return super.dispatchSelectionEvent(event);
        }
        super.dispatchSelectionEvent(const ClearSelectionEvent());
        return result;
      default:
        return super.dispatchSelectionEvent(event);
    }
  }
}

/// [child] in full up to [maxHeight]; past that, its top [maxHeight],
/// fading out through its alpha towards the bottom (as a long message in
/// the history does), what is behind it showing through.
class _FadedBody extends SingleChildRenderObjectWidget {
  const _FadedBody({required this.maxHeight, required super.child});

  final double maxHeight;

  @override
  _RenderFadedBody createRenderObject(BuildContext context) =>
      _RenderFadedBody(maxHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderFadedBody renderObject) {
    renderObject.maxHeight = maxHeight;
  }
}

class _RenderFadedBody extends RenderProxyBox {
  _RenderFadedBody(this._maxHeight);

  double _maxHeight;
  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  /// Over how much of the bottom it fades out.
  static const _fadeLength = 56.0;

  /// How far above the bottom it is hidden completely: the eased end of a
  /// fade is faint but not zero, and would show the tops of the last
  /// line's glyphs.
  static const _fadeOffset = 6.0;

  bool _overflows = false;
  final _maskLayer = LayerHandle<ShaderMaskLayer>();

  @override
  bool get alwaysNeedsCompositing => _overflows;

  @override
  void dispose() {
    _maskLayer.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final overflows = child.size.height > _maxHeight;
    if (overflows != _overflows) {
      _overflows = overflows;
      markNeedsCompositingBitsUpdate();
    }
    size = constraints.constrain(
      Size(child.size.width, overflows ? _maxHeight : child.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child!;
    if (!_overflows) {
      _maskLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    final fade = Rect.fromLTRB(
      0,
      size.height - _fadeLength - _fadeOffset,
      size.width,
      size.height - _fadeOffset,
    );
    final samples = easedFade().toList().reversed;
    _maskLayer.layer = (_maskLayer.layer ?? ShaderMaskLayer())
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (final (_, opacity) in samples)
            Color.fromRGBO(255, 255, 255, opacity),
        ],
        stops: [for (final (t, _) in samples) 1 - t],
      ).createShader(fade)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      _maskLayer.layer!,
      (context, offset) => context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => context.paintChild(child, offset),
      ),
      offset,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _overflows ? Offset.zero & size : null;

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(width).clamp(0, _maxHeight);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(width).clamp(0, _maxHeight);
}
