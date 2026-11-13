import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../chat_models.dart';
import '../markdown/file_link.dart' show FileLink;
import 'step_header.dart';
import 'step_images.dart';
import 'strings.dart';
import '../../theme/app_theme.dart';

/// A message to another agent's icon (Remix Icon's speak-ai-line).
const speakIcon = 'assets/icons/speak-ai-line.svg';

/// A todo's mark by its status (Remix Icon's): done, in progress, to do.
const todoDoneIcon = 'assets/icons/checkbox-circle-fill.svg';
const todoDoingIcon = 'assets/icons/progress-4-line.svg';
const todoOpenIcon = 'assets/icons/checkbox-blank-circle-line.svg';

/// The tool rows' and todo lists' strings, both languages inline: the
/// desktop reads them from `AppLocalizations`; the mobile has no l10n
/// class, and the widgets sit below where an `AppState` would reach.
class ToolStrings {
  const ToolStrings._(this.zh);

  factory ToolStrings(bool zh) => zh ? zhCN : en;

  /// Per the platform locale; a call site with an `AppState` passes
  /// `ToolStrings(state.tr('中', 'en') == '中')`.
  factory ToolStrings.standard() => ToolStrings(localeIsZh);

  static const zhCN = ToolStrings._(true);
  static const en = ToolStrings._(false);

  final bool zh;

  String _t(String zhText, String enText) => zh ? zhText : enText;

  String toolVerbLabel(
    ToolKind kind, {
    ToolStatus status = ToolStatus.succeeded,
  }) {
    if (status == ToolStatus.denied) return _t('已拒绝', 'Denied');
    if (status == ToolStatus.failed) return _t('执行失败', 'Failed');
    final running = status == ToolStatus.running;
    return _t(
      switch (kind) {
        ToolKind.read => running ? '正在读取' : '已读取',
        ToolKind.grep => running ? '正在搜索' : '已搜索',
        ToolKind.listDir => running ? '正在列出' : '已列出',
        ToolKind.search => running ? '正在搜索' : '已搜索',
        ToolKind.edit => running ? '正在编辑' : '已编辑',
        ToolKind.command => running ? '正在运行' : '已运行',
        ToolKind.web => running ? '正在获取' : '已获取',
        ToolKind.agent => '智能体',
        ToolKind.mcp => 'MCP',
        ToolKind.todo => running ? '正在更新待办' : '已更新待办',
        ToolKind.message => running ? '正在说' : '说',
        // Refused: answered for the user, not asked.
        ToolKind.question =>
          running
              ? '正在提问'
              : status == ToolStatus.denied
              ? '已跳过提问'
              : '提问',
        ToolKind.goal => running ? '正在提议目标' : '提议目标',
        ToolKind.image =>
          running
              ? '正在生成图片'
              : status == ToolStatus.succeeded
              ? '已生成图片'
              : '图片未生成',
        ToolKind.browser || ToolKind.other => running ? '正在使用' : '已使用',
      },
      switch (kind) {
        ToolKind.read => running ? 'Reading' : 'Read',
        ToolKind.grep => running ? 'Grepping' : 'Grepped',
        ToolKind.listDir => running ? 'Listing' : 'Listed',
        ToolKind.search => running ? 'Searching' : 'Searched',
        ToolKind.edit => running ? 'Editing' : 'Edited',
        ToolKind.command => running ? 'Running' : 'Ran',
        ToolKind.web => running ? 'Fetching' : 'Fetched',
        ToolKind.agent => 'Agent',
        ToolKind.mcp => 'MCP',
        ToolKind.todo => running ? 'Updating todos' : 'Updated todos',
        ToolKind.message => running ? 'Saying' : 'Said',
        ToolKind.question =>
          running
              ? 'Asking'
              : status == ToolStatus.denied
              ? 'Skipped question'
              : 'Asked',
        ToolKind.goal => running ? 'Proposing a goal' : 'Proposed a goal',
        ToolKind.image =>
          running
              ? 'Generating image'
              : status == ToolStatus.succeeded
              ? 'Generated image'
              : 'Image not generated',
        ToolKind.browser || ToolKind.other => running ? 'Using' : 'Used',
      },
    );
  }

  /// "待办 1/3" / "Todos 1/3".
  String todoCount(int done, int total) =>
      _t('待办 $done/$total', 'Todos $done/$total');

  String get todoAllDone => _t('全部完成', 'All done');
  String get todoChecked => _t('查看待办', 'Checked todos');
  String get todoNone => _t('列表为空', 'List empty');
  String get todoAdded => _t('添加待办', 'Added todo');
  String get todoStarted => _t('开始待办', 'Started todo');
  String get todoCompleted => _t('完成待办', 'Completed todo');
  String get todoRemoved => _t('删除待办', 'Removed todo');
  String get todoUpdated => _t('更新待办', 'Updated todo');
  String get goalAdopt => _t('设为目标', 'Set as goal');
  String get goalAdopted => _t('已设为目标', 'Goal set');
  String get openFile => _t('打开文件', 'Open file');
}

/// One tool call as a step, e.g. "Read main.dart L1-562"; opens to what it
/// found or returned, when there is anything. Mobile adaptation: the
/// desktop's hover path tooltip and right-click file menu become nothing
/// (the detail line and the opened body carry it), and [onOpenFile] —
/// wired to the paired desktop's read — opens the file instead of the
/// desktop's side panel.
class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    super.key,
    required this.kind,
    required this.target,
    this.detail,
    this.path,
    this.results = const [],
    this.label,
    this.tool,
    this.input = const {},
    this.status = ToolStatus.succeeded,
    this.output,
    this.images = const [],
    this.imageFiles = const [],
    this.expanded = false,
    this.onToggle,
    this.onSetGoal,
    this.strings,
    this.onOpenFile,
  });

  final ToolKind kind;
  final String target;
  final String? detail;
  final String? path;
  final List<String> results;
  final String? label;

  /// The tool's own name and what it was called with, for a kind each of
  /// whose tools says its own way (see [todoStep]).
  final String? tool;
  final Map<String, Object?> input;
  final ToolStatus status;
  final String? output;

  /// The pictures it returned (an image file read, a screenshot), shown
  /// under what it said as they are.
  final List<ImageAttachment> images;

  /// CLI 保存的图片路径（见 [ToolCallItem.imageFiles]）；手机暂不按这些路径读取图片。
  final List<String> imageFiles;

  final bool expanded;
  final VoidCallback? onToggle;

  /// Sets a proposed goal ([ToolKind.goal]; its condition the output).
  final ValueChanged<String>? onSetGoal;

  final ToolStrings? strings;

  /// Reads the file off the paired desktop; null, it cannot.
  final void Function(String path)? onOpenFile;

  List<ImageAttachment> get _images =>
      status == ToolStatus.failed ? const [] : images;

  bool get _running => status == ToolStatus.running;

  /// The desktop's tool labels are English; a Chinese reader gets our verb.
  String? _localizedLabel(ToolStrings s) =>
      s.zh && label != null && !_cjk.hasMatch(label!) ? null : label;

  /// An absolute path's shared prefix pushes the file name out of the single
  /// line, so it shows the name; opening the file shows the rest.
  String get _shortTarget =>
      (kind == ToolKind.read || kind == ToolKind.edit) &&
          _absolutePath.hasMatch(target)
      ? target.split(RegExp(r'[\\/]')).last
      : target;

  static final _cjk = RegExp(r'[\u4e00-\u9fff]');
  static final _absolutePath = RegExp(r'^([A-Za-z]:[\\/]|/)');

  String? get _shown => switch (output?.trimRight()) {
    final text? when text.isNotEmpty => text,
    _ => null,
  };

  bool get _opens => results.isNotEmpty || _shown != null || images.isNotEmpty;

  /// The list written or read, each item marked by its status (its
  /// output says it as text).
  List<TodoItem>? get _todos => status == ToolStatus.failed
      ? null
      : switch (todoItems(tool, input, output)) {
          final todos? when todos.isNotEmpty => todos,
          _ => null,
        };

  /// The file read or written, where [onOpenFile] can open it.
  String? get _file {
    final path = this.path;
    if (onOpenFile == null || path == null) return null;
    if (kind != ToolKind.read && kind != ToolKind.edit) return null;
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final s = strings ?? ToolStrings.standard();
    final todo = kind == ToolKind.todo
        ? todoStep(tool, input, target, output: output, strings: s)
        : null;
    final header = StepHeader(
      verb: status == ToolStatus.denied || status == ToolStatus.failed
          ? s.toolVerbLabel(kind, status: status)
          : _localizedLabel(s) ??
                todo?.verb ??
                s.toolVerbLabel(kind, status: status),
      object: todo?.object ?? _shortTarget,
      detail: todo?.detail ?? detail,
      running: _running,
      expanded: expanded,
      onToggle: _opens ? onToggle : null,
      onOpen: file == null ? null : () => onOpenFile!(file),
      openTooltip: file == null ? null : s.openFile,
      icon: switch (kind) {
        // A message to another agent: someone speaking, standing out.
        ToolKind.message => SvgPicture.asset(
          speakIcon,
          width: 15,
          height: 15,
          colorFilter: const ColorFilter.mode(amber, BlendMode.srcIn),
        ),
        ToolKind.goal => Icon(Icons.flag_outlined, size: 15, color: amber),
        ToolKind.todo => Icon(
          Icons.checklist_rounded,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        _ => null,
      },
      action: switch ((kind, _shown, onSetGoal)) {
        (ToolKind.goal, final condition?, final set?) when !_running =>
          _SetGoalButton(onTap: () => set(condition), strings: s),
        _ => null,
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (_todos case final todos? when expanded)
          StepBody(
            child: _TodoList(todos: todos, strings: s),
          )
        else if (expanded && (results.isNotEmpty || _shown != null))
          StepBody(
            child: results.isNotEmpty && onOpenFile != null
                ? _Results(
                    results: results,
                    strings: s,
                    onOpenFile: onOpenFile!,
                  )
                : Text(
                    results.isNotEmpty ? results.join('\n') : _shown!,
                    style: stepMono(context),
                  ),
          ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 6),
          ToolImages(images: _images),
        ],
      ],
    );
  }

  /// The accent's amber, where the desktop reads the theme's event color:
  /// warm, standing out without the warning's mustard.
  static const amber = Color(0xFF966A25);
}

/// A todo list, each item after its mark: done ones faint and struck
/// through, as the todo panel had them.
class _TodoList extends StatelessWidget {
  const _TodoList({required this.todos, required this.strings});

  final List<TodoItem> todos;
  final ToolStrings? strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final doneFaint = scheme.onSurfaceVariant.withValues(
      alpha: MobileTheme.asideAlpha,
    );
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final todo in todos) _item(todo, scheme, doneFaint, dark),
      ],
    );
  }

  Widget _item(TodoItem todo, ColorScheme scheme, Color doneFaint, bool dark) {
    final done = todo.status == 'completed';
    final (icon, color) = switch (todo.status) {
      'completed' => (todoDoneIcon, const Color(0xFF3FB950)),
      'in_progress' => (todoDoingIcon, const Color(0xFF4493F8)),
      _ => (todoOpenIcon, scheme.onSurfaceVariant),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SvgPicture.asset(
            icon,
            width: 14,
            height: 14,
            colorFilter: ColorFilter.mode(
              dark
                  ? (todo.status == 'completed'
                        ? const Color(0xFF2EA043)
                        : todo.status == 'in_progress'
                        ? const Color(0xFF58A6FF)
                        : color)
                  : color,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            todo.content,
            style: TextStyle(
              color: done ? doneFaint : scheme.onSurface,
              fontSize: MobileType.secondary,
              height: 1.6,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: doneFaint,
            ),
          ),
        ),
      ],
    );
  }
}

/// A search's matches (`path`, `path:line`), each opening its file on the
/// desktop.
class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.strings,
    required this.onOpenFile,
  });

  final List<String> results;
  final ToolStrings? strings;
  final void Function(String path) onOpenFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final result in results) _result(context, result)],
    );
  }

  Widget _result(BuildContext context, String result) {
    final link = FileLink.parseText(result, blanks: true);
    final text = Text(result, style: stepMono(context));
    if (link == null) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenFile(link.path),
      child: Text(
        result,
        style: stepMono(context).copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}

/// An item of a todo list, and its status: `pending`, `in_progress` or
/// `completed`.
typedef TodoItem = ({String content, String status});

/// The items of the todo list a call wrote (TodoWrite) or read (TaskList,
/// from the lines it returned: `#1 [completed] Ship it`); null for another
/// call.
List<TodoItem>? todoItems(
  String? tool,
  Map<String, Object?> input,
  String? output,
) => switch (tool) {
  'TodoWrite' => [
    for (final todo in input['todos'] as List? ?? const [])
      if (todo is Map)
        (
          content: '${todo['content'] ?? ''}',
          status: '${todo['status'] ?? 'pending'}',
        ),
  ],
  'TaskList' => [
    for (final line in const LineSplitter().convert(output ?? ''))
      if (_taskLine.firstMatch(line) case final match?)
        (content: match[2]!, status: match[1]!),
  ],
  _ => null,
};

final _taskLine = RegExp(r'^#\S+ \[(\w+)\] (.+)$');

/// What a call of a todo tool ([ToolKind.todo]) did to the list, as
/// [tool], its [input] and [output] say, and what about: "Todos 1/3" and
/// the item in progress (the call's [target]), "Added todo" and the item,
/// "Checked todos", the item in progress and "1/3"; null for another tool,
/// or a list not written yet.
({String verb, String object, String? detail})? todoStep(
  String? tool,
  Map<String, Object?> input,
  String target, {
  String? output,
  ToolStrings? strings,
}) {
  final s = strings ?? ToolStrings.standard();
  final todos = todoItems(tool, input, output);
  final done = todos?.where((todo) => todo.status == 'completed').length;
  switch (tool) {
    case 'TodoWrite':
      if (todos == null || todos.isEmpty) return null;
      return (
        verb: s.todoCount(done!, todos.length),
        object: target.isEmpty && done == todos.length ? s.todoAllDone : target,
        detail: null,
      );
    // Read: what is in progress, and how far the list is.
    case 'TaskList':
      if (todos == null || todos.isEmpty) {
        return (
          verb: s.todoChecked,
          object: output == null ? '' : s.todoNone,
          detail: null,
        );
      }
      return (
        verb: s.todoChecked,
        object:
            todos
                .where((todo) => todo.status == 'in_progress')
                .firstOrNull
                ?.content ??
            (done == todos.length ? s.todoAllDone : ''),
        detail: '$done/${todos.length}',
      );
  }
  final verb = switch (tool) {
    'TaskCreate' => s.todoAdded,
    'TaskUpdate' => switch (input['status']) {
      'in_progress' => s.todoStarted,
      'completed' => s.todoCompleted,
      'deleted' => s.todoRemoved,
      _ => s.todoUpdated,
    },
    'TaskGet' => s.todoChecked,
    _ => null,
  };
  return verb == null ? null : (verb: verb, object: target, detail: null);
}

/// What a kind of tool call did, or does while running, as its [status]
/// says.
String toolVerb(
  ToolKind kind, {
  ToolStatus status = ToolStatus.succeeded,
  ToolStrings? strings,
}) => (strings ?? ToolStrings.standard()).toolVerbLabel(kind, status: status);

/// Sets a proposed goal; once it has, says so.
class _SetGoalButton extends StatefulWidget {
  const _SetGoalButton({required this.onTap, required this.strings});

  final VoidCallback onTap;
  final ToolStrings? strings;

  @override
  State<_SetGoalButton> createState() => _SetGoalButtonState();
}

class _SetGoalButtonState extends State<_SetGoalButton> {
  bool _set = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = widget.strings ?? ToolStrings.standard();
    if (_set) {
      return Text(
        strings.goalAdopted,
        style: TextStyle(
          color: scheme.onSurfaceVariant.withValues(
            alpha: MobileTheme.asideAlpha,
          ),
          fontSize: MobileType.aside,
        ),
      );
    }
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: () {
          setState(() => _set = true);
          widget.onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            strings.goalAdopt,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: MobileType.caption,
            ),
          ),
        ),
      ),
    );
  }
}
