import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import '../../link/phone_link.dart' show KeptDesktop;
import '../../state/app_state.dart';
import '../../platform/file_export.dart';
import '../../chat/markdown/markdown_view.dart';
import '../../theme/material_file_icons.dart' as material_icons;
import '../../theme/app_theme.dart';
import '../conversations/conversation_filters.dart'
    show ConversationSource, projectSource;
import '../conversations/project_actions.dart';
import '../devices/device_menu.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/bottom_sheet_panel.dart';
import '../widgets/dropdown_panel.dart';
import 'file_source_view.dart';
import 'diff_lines.dart';
import 'line_diff.dart';
import 'markdown_image.dart';
import 'page_zoom.dart';
import '../user_message.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.state});
  final AppState state;
  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  AppState get state => widget.state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final desktop = state.desktops
          .where((desktop) => desktop.id == state.selectedDesktopId)
          .firstOrNull;
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: DesktopSwitcherTitle(state: state),
        ),
        body: desktop == null
            ? EmptyPanel(
                state.tr(
                  '连接电脑以浏览项目文件',
                  'Connect a desktop to browse project files',
                ),
                icon: Icons.folder_outlined,
              )
            : ListView(children: _desktop(context, desktop)),
      );
    },
  );

  List<Widget> _desktop(BuildContext context, KeptDesktop desktop) => [
    for (final ref in state.projects.where(
      (ref) => ref.desktopId == desktop.id,
    )) ...[
      ProjectActionRow(
        key: ValueKey('project-swipe-${desktop.id}-${ref.project.id}'),
        state: state,
        project: ref,
        child: ListRow(
          key: ValueKey('project-actions-${desktop.id}-${ref.project.id}'),
          leading: const Center(child: material_icons.FolderIcon('', size: 36)),
          title: ref.project.name,
          note: switch (projectSource(ref.project.id)) {
            ConversationSource.ssh => 'SSH',
            ConversationSource.wsl => 'WSL',
            _ => null,
          },
          subtitle: shortPath(ref.project.path),
          trailing: LucideIcon(
            'chevron-right',
            size: 18,
            color: Theme.of(context).hintColor,
          ),
          onTap: state.isOnline(desktop.id)
              ? () => openPage<void>(
                  context,
                  FilesPage(state: state, project: ref),
                )
              : null,
        ),
      ),
    ],
    if (!state.isOnline(desktop.id) ||
        !state.projects.any((ref) => ref.desktopId == desktop.id))
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          state.isOnline(desktop.id)
              ? state.tr('没有打开的项目', 'No open projects')
              : state.tr('电脑离线', 'Desktop offline'),
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      ),
  ];
}

/// Git 忽略的文件比正常的淡，和电脑端一样一眼能分开。
const _ignoredOpacity = .5;

class FilesPage extends StatefulWidget {
  const FilesPage({
    super.key,
    required this.state,
    required this.project,
    this.prefix = '',
    this.listing,
    this.picking = false,
  });
  final AppState state;
  final ProjectRef project;
  final String prefix;
  final Map<String, Object?>? listing;

  /// 对话里 @ 文件时用：点文件不打开，而是把它的路径带回去（一层层退回）。
  final bool picking;
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  late Future<Map<String, Object?>> _listing;
  String _query = '';
  bool _grid = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final listing = widget.listing == null
        ? widget.state
              .request(widget.project.desktopId, LinkMethods.files, {
                'project': widget.project.project.id,
              })
              .then(objectMap)
        : Future.value(widget.listing!);
    _listing = listing.then(
      (listing) async => {...listing, 'disk': await _disk()},
    );
  }

  /// 这一层在磁盘上的内容，`files` 不列的（Git 忽略的、构建产物）靠它补上。
  /// 没有这个方法的旧电脑端，或这一层已不在磁盘上时，就只看 `files`。
  Future<Map<String, Object?>> _disk() async {
    final prefix = widget.prefix;
    try {
      return objectMap(
        await widget.state.request(
          widget.project.desktopId,
          LinkMethods.folder,
          {
            'project': widget.project.project.id,
            'path': prefix.endsWith('/')
                ? prefix.substring(0, prefix.length - 1)
                : prefix,
          },
        ),
      );
    } on LinkRemoteException catch (error) {
      if (error.code == LinkErrors.unknown ||
          error.code == LinkErrors.notFound) {
        return const {};
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(
        leading: widget.prefix.isEmpty
            ? null
            : BackButton(onPressed: () => Navigator.maybePop(context)),
        title: Text(
          widget.picking && widget.prefix.isEmpty
              ? state.tr('选择要引用的文件', 'Pick a file to mention')
              : widget.prefix.isEmpty
              ? widget.project.project.name
              : widget.prefix.split('/').where((part) => part.isNotEmpty).last,
        ),
        actions: [
          if (widget.prefix.isEmpty)
            IconButton(
              icon: const LucideIcon('refresh-cw', size: 20),
              onPressed: () => setState(_load),
            ),
        ],
      ),
      body: Column(
        children: [
          SearchCapsule(
            state: state,
            hint: state.tr('转到文件', 'Go to file'),
            onChanged: (text) => setState(() => _query = text),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: widget.prefix.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          [
                            widget.project.project.name,
                            ...widget.prefix
                                .split('/')
                                .where((part) => part.isNotEmpty),
                          ].join(' › '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                ),
                Container(
                  key: const ValueKey('file-view-switch'),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(MobileSizes.radius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final grid in [false, true])
                        Container(
                          key: ValueKey(
                            grid ? 'file-grid-option' : 'file-list-option',
                          ),
                          decoration: BoxDecoration(
                            color: _grid == grid
                                ? segmentThumbColor(context)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: IconButton(
                            isSelected: _grid == grid,
                            tooltip: grid
                                ? state.tr('网格视图', 'Grid view')
                                : state.tr('列表视图', 'List view'),
                            onPressed: () => setState(() => _grid = grid),
                            icon: LucideIcon(
                              grid ? 'layout-grid' : 'list',
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, Object?>>(
              future: _listing,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyPanel(
                    userMessage(state, snapshot.error),
                    actionLabel: state.tr('重试', 'Retry'),
                    onAction: () => setState(_load),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final listing = snapshot.data!;
                final paths = ((listing['paths'] as List?) ?? [])
                    .whereType<String>();
                final changes = objectMap(listing['changes']);
                final names = <String, bool>{};
                for (final path in paths) {
                  if (_query.isNotEmpty) {
                    if (path.toLowerCase().contains(_query.toLowerCase())) {
                      names[path] = false;
                    }
                  } else if (path.startsWith(widget.prefix)) {
                    final relative = path.substring(widget.prefix.length);
                    if (relative.isEmpty) continue;
                    final slash = relative.indexOf('/');
                    names[slash < 0 ? relative : relative.substring(0, slash)] =
                        slash >= 0;
                  }
                }
                // 只在磁盘上有的，灰着显示。
                final ignored = <String>{};
                if (_query.isEmpty) {
                  final disk = objectMap(listing['disk']);
                  for (final (key, directory) in const [
                    ('folders', true),
                    ('files', false),
                  ]) {
                    for (final name
                        in ((disk[key] as List?) ?? const [])
                            .whereType<String>()) {
                      if (names.containsKey(name)) continue;
                      names[name] = directory;
                      ignored.add(name);
                    }
                  }
                }
                final entries = names.entries.toList()
                  ..sort((a, b) {
                    if (a.value != b.value) return a.value ? -1 : 1;
                    return a.key.toLowerCase().compareTo(b.key.toLowerCase());
                  });
                final directChildren = <String, Set<String>>{};
                for (final path in paths) {
                  if (!path.startsWith(widget.prefix)) continue;
                  final relative = path.substring(widget.prefix.length);
                  final slash = relative.indexOf('/');
                  if (slash > 0) {
                    final directory = relative.substring(0, slash);
                    final child = relative
                        .substring(slash + 1)
                        .split('/')
                        .first;
                    if (child.isNotEmpty) {
                      (directChildren[directory] ??= {}).add(child);
                    }
                  }
                }
                final directChildCounts = directChildren.map(
                  (name, children) => MapEntry(name, children.length),
                );
                final truncated = listing['truncated'] == true;
                final entryWidgets = [
                  for (final entry in entries)
                    _grid
                        ? InkWell(
                            onTap: () => _openEntry(
                              context,
                              state,
                              listing,
                              entry.key,
                              entry.value,
                            ),
                            child: Opacity(
                              opacity: ignored.contains(entry.key)
                                  ? _ignoredOpacity
                                  : 1,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    entry.value
                                        ? material_icons.FolderIcon(
                                            entry.key,
                                            size: 42,
                                          )
                                        : material_icons.FileIcon(
                                            entry.key,
                                            size: 42,
                                          ),
                                    const SizedBox(height: 8),
                                    Text(
                                      entry.key,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    if (entry.value &&
                                        !truncated &&
                                        directChildCounts.containsKey(
                                          entry.key,
                                        ))
                                      Text(
                                        '${directChildCounts[entry.key]} ${state.tr('项', 'items')}',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : _FileRow(
                            name: entry.key,
                            directory: entry.value,
                            ignored: ignored.contains(entry.key),
                            count: entry.value && !truncated
                                ? directChildCounts[entry.key]
                                : null,
                            change: entry.value
                                ? null
                                : changes[_query.isEmpty
                                          ? '${widget.prefix}${entry.key}'
                                          : entry.key]
                                      as String?,
                            tr: state.tr,
                            onTap: () => _openEntry(
                              context,
                              state,
                              listing,
                              entry.key,
                              entry.value,
                            ),
                          ),
                ];
                final listingView = _grid
                    ? GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisExtent:
                              42 +
                              8 +
                              24 +
                              MediaQuery.textScalerOf(context).scale(15) *
                                  1.4 *
                                  3,
                        ),
                        itemCount: entryWidgets.length,
                        itemBuilder: (context, index) => entryWidgets[index],
                      )
                    : ListView(children: entryWidgets);
                return Column(
                  children: [
                    if (truncated)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            state.tr(
                              '文件列表达到上限，未列出所有文件。',
                              'The file listing reached its limit.',
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: entries.isEmpty
                          ? EmptyPanel(
                              state.tr('没有文件', 'No files'),
                              icon: Icons.folder_open_outlined,
                            )
                          : listingView,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEntry(
    BuildContext context,
    AppState state,
    Map<String, Object?> listing,
    String name,
    bool directory,
  ) async {
    final path = _query.isEmpty ? '${widget.prefix}$name' : name;
    if (widget.picking && !directory) {
      Navigator.pop(context, path);
      return;
    }
    final picked = await openPage<String>(
      context,
      directory
          ? FilesPage(
              state: state,
              project: widget.project,
              prefix: '$path/',
              listing: listing,
              picking: widget.picking,
            )
          : FileViewerPage(state: state, project: widget.project, path: path),
    );
    // 下一层选中了文件：接着往回退，把路径带给打开选择的地方。
    if (picked != null && context.mounted) Navigator.pop(context, picked);
  }
}

class FileViewerPage extends StatefulWidget {
  const FileViewerPage({
    super.key,
    required this.state,
    required this.project,
    required this.path,
    this.sessionId,
  });
  final AppState state;
  final ProjectRef project;
  final String path;
  final String? sessionId;
  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

enum _FileMode { preview, source, diff }

enum _FileAction {
  wrap,
  jump,
  larger,
  smaller,
  copyPath,
  copyContent,
  download,
}

class _FileViewerPageState extends State<FileViewerPage> {
  late Future<Map<String, Object?>> _file;
  final _search = TextEditingController();
  bool _downloading = false, _wrap = false, _searching = false;
  _FileMode? _mode;
  double? _fontSize;
  List<RegExpMatch> _matches = const [];
  int _activeMatch = 0, _navigationRevision = 0;
  int? _targetLine;
  final _pictures = <String, Future<Uint8List>>{};

  Future<Uint8List> _picture(String path) =>
      _pictures.putIfAbsent(path, () async {
        final data = objectMap(
          await widget.state.request(
            widget.project.desktopId,
            LinkMethods.image,
            {'project': widget.project.project.id, 'path': path},
          ),
        );
        final encoded = data['data'];
        if (encoded is! String) throw const FormatException('no image data');
        return base64Decode(encoded);
      });

  Widget _markdownImage(
    String src,
    String alt,
    String? title, {
    double? width,
    double? height,
  }) {
    final path = markdownImagePath(widget.path, src);
    if (path == null) return Text('[${alt.isEmpty ? 'image' : alt}]');
    return MarkdownFileImage(bytes: _picture(path), alt: alt, width: width);
  }

  bool get _markdown => RegExp(
    r'\.(md|markdown|mdown|mkd)$',
    caseSensitive: false,
  ).hasMatch(widget.path);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _FileMode _viewMode(Map<String, Object?> data) {
    final mode =
        _mode ??
        (data['original'] is String
            ? _FileMode.diff
            : _markdown
            ? _FileMode.preview
            : _FileMode.source);
    if (mode == _FileMode.diff && data['original'] is! String) {
      return _markdown ? _FileMode.preview : _FileMode.source;
    }
    return mode;
  }

  void _find(String text, String query) {
    setState(() {
      _matches = query.isEmpty
          ? const []
          : RegExp(
              RegExp.escape(query),
              caseSensitive: false,
            ).allMatches(text).toList();
      _activeMatch = 0;
      _locateMatch(text);
    });
  }

  void _locateMatch(String text) {
    if (_matches.isEmpty) {
      _targetLine = null;
      return;
    }
    _targetLine =
        '\n'
            .allMatches(text.substring(0, _matches[_activeMatch].start))
            .length +
        1;
    _navigationRevision++;
  }

  void _nextMatch(String text, int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _activeMatch = (_activeMatch + delta) % _matches.length;
      _locateMatch(text);
    });
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
    _matches = const [];
    _targetLine = null;
  });

  Future<void> _jump(String text) async {
    final line = await showDialog<int>(
      context: context,
      builder: (_) => _JumpToLineDialog(
        state: widget.state,
        lineCount: text.split('\n').length,
      ),
    );
    if (!mounted || line == null) return;
    setState(() {
      _mode = _FileMode.source;
      _searching = false;
      _search.clear();
      _matches = const [];
      _targetLine = line;
      _navigationRevision++;
    });
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.state.tr('已复制', 'Copied'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.state.tr('复制失败，请重试。', 'Copy failed. Please try again.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _more(BuildContext anchor, Map<String, Object?>? data) async {
    final state = widget.state;
    final text = data?['text'] as String?;
    final source =
        data != null && _viewMode(data) == _FileMode.source && text != null;
    final size = _fontSize ?? MobileTheme.codeFontSizeOf(context);
    MenuPanelItem<_FileAction> item(
      _FileAction action,
      IconData icon,
      String label, {
      Widget? trailing,
      bool selected = false,
      bool enabled = true,
    }) => MenuPanelItem(
      action,
      label,
      leading: Icon(icon, size: 22),
      trailing: trailing,
      selected: selected,
      enabled: enabled,
    );
    final action = await showMenuPanel<_FileAction>(anchor, [
      if (source)
        item(
          _FileAction.wrap,
          Icons.wrap_text,
          state.tr('自动换行', 'Word wrap'),
          selected: _wrap,
        ),
      if (text != null)
        item(_FileAction.jump, Icons.numbers, state.tr('跳到行', 'Go to line')),
      if (source) ...[
        item(
          _FileAction.larger,
          Icons.zoom_in,
          state.tr('放大字号', 'Increase font size'),
          trailing: Text(size.toStringAsFixed(0)),
          enabled: size < 24,
        ),
        item(
          _FileAction.smaller,
          Icons.zoom_out,
          state.tr('缩小字号', 'Decrease font size'),
          enabled: size > 10,
        ),
      ],
      item(_FileAction.copyPath, Icons.link, state.tr('复制路径', 'Copy path')),
      if (text != null)
        item(
          _FileAction.copyContent,
          Icons.copy,
          state.tr('复制内容', 'Copy contents'),
        ),
      item(
        _FileAction.download,
        Icons.download_outlined,
        state.tr('下载文件', 'Download file'),
        enabled: !_downloading && state.isOnline(widget.project.desktopId),
      ),
    ], width: 240);
    if (!mounted || action == null) return;
    switch (action) {
      case _FileAction.wrap:
        setState(() => _wrap = !_wrap);
      case _FileAction.jump:
        if (text != null) await _jump(text);
      case _FileAction.larger:
        setState(() => _fontSize = (size + 2).clamp(10, 24).toDouble());
      case _FileAction.smaller:
        setState(() => _fontSize = (size - 2).clamp(10, 24).toDouble());
      case _FileAction.copyPath:
        await _copy(widget.path);
      case _FileAction.copyContent:
        if (text != null) await _copy(text);
      case _FileAction.download:
        await _download();
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await runUi(context, () async {
        final result = await widget.state.request(
          widget.project.desktopId,
          LinkMethods.download,
          {'project': widget.project.project.id, 'path': widget.path},
        );
        if (!mounted) return;
        final bytes = decodeFileDownload(result);
        final saved = await saveFile(widget.path.split('/').last, bytes);
        if (saved && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.state.tr('文件已保存', 'File saved'))),
          );
        }
      }, errorMessage: (error) => userMessage(widget.state, error));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  bool get _image => RegExp(
    r'\.(png|jpe?g|gif|webp)$',
    caseSensitive: false,
  ).hasMatch(widget.path);
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _search.clear();
    _pictures.clear();
    _matches = const [];
    _targetLine = null;
    _searching = false;
    _file = widget.state
        .request(
          widget.project.desktopId,
          _image ? LinkMethods.image : LinkMethods.read,
          {'project': widget.project.project.id, 'path': widget.path},
        )
        .then(objectMap);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
    future: _file,
    builder: (context, snapshot) {
      final state = widget.state;
      final data = snapshot.data;
      final readable =
          data?['text'] is String &&
          data?['tooLarge'] != true &&
          data?['binary'] != true &&
          !snapshot.hasError;
      final text = readable ? data!['text'] as String : '';
      return MobileTheme.reading(
        context,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (readable)
                IconButton(
                  tooltip: state.tr('搜索文件内容', 'Search file contents'),
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() {
                    _searching = true;
                    _mode = _FileMode.source;
                  }),
                )
              else
                IconButton(
                  tooltip: state.tr('下载文件', 'Download file'),
                  icon: const Icon(Icons.download_outlined, size: 20),
                  onPressed:
                      _downloading || !state.isOnline(widget.project.desktopId)
                      ? null
                      : _download,
                ),
              Builder(
                builder: (anchor) => IconButton(
                  tooltip: state.tr('更多文件操作', 'More file actions'),
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => _more(anchor, readable ? data : null),
                ),
              ),
            ],
          ),
          body: snapshot.hasError
              ? EmptyPanel(
                  userMessage(state, snapshot.error),
                  actionLabel: state.tr('重试', 'Retry'),
                  onAction: () => setState(_load),
                )
              : data == null
              ? const Center(child: CircularProgressIndicator())
              : _contents(data, text),
        ),
      );
    },
  );

  Widget _contents(Map<String, Object?> data, String text) {
    final state = widget.state;
    if (data['tooLarge'] == true) {
      return EmptyPanel(
        state.tr(
          '文件过大，无法在手机读取。',
          'This file is too large to read on the phone.',
        ),
        icon: Icons.insert_drive_file_outlined,
      );
    }
    if (data['binary'] == true) {
      return EmptyPanel(
        state.tr('无法预览二进制文件', 'Binary file preview is not available'),
        icon: Icons.insert_drive_file_outlined,
      );
    }
    if (_image && data['data'] is String) {
      final Uint8List bytes;
      try {
        bytes = base64Decode(data['data'] as String);
      } on FormatException {
        return EmptyPanel(state.tr('图片数据无效', 'Invalid image data'));
      }
      return Stack(
        children: [
          InteractiveViewer(
            minScale: 0.25,
            maxScale: 8,
            child: Center(
              child: Image.memory(
                bytes,
                errorBuilder: (_, _, _) =>
                    Text(state.tr('无法解码图片', 'Cannot decode this image')),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'save-image',
              onPressed: () =>
                  saveImageToGallery(context, bytes, album: 'YCode'),
              icon: const Icon(Icons.save_alt),
              label: Text(state.tr('保存到相册', 'Save to gallery')),
            ),
          ),
        ],
      );
    }
    final original = data['original'] as String?;
    final mode = _viewMode(data);
    final theme = Theme.of(context);
    // 预览按段切好，列表只为看得见的段建控件。
    final preview = mode == _FileMode.preview
        ? markdownSegmentNodes(text)
        : const <List<md.Node>>[];
    return Column(
      children: [
        if (_markdown || original != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentBar<_FileMode>(
              values: [
                if (_markdown) _FileMode.preview,
                _FileMode.source,
                if (original != null) _FileMode.diff,
              ],
              selected: mode,
              label: (value) => switch (value) {
                _FileMode.preview => state.tr('预览', 'Preview'),
                _FileMode.source => state.tr('源码', 'Source'),
                _FileMode.diff => state.tr('差异', 'Diff'),
              },
              onSelected: (value) => setState(() {
                _mode = value;
                if (_mode != _FileMode.source) {
                  _searching = false;
                  _search.clear();
                  _matches = const [];
                  _targetLine = null;
                }
              }),
            ),
          ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('file-content-search'),
                    controller: _search,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: state.tr('搜索文件内容', 'Search file contents'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      suffixText:
                          '${_matches.isEmpty ? 0 : _activeMatch + 1} / ${_matches.length}',
                    ),
                    onChanged: (query) => _find(text, query),
                    onSubmitted: (_) => _nextMatch(text, 1),
                  ),
                ),
                IconButton(
                  tooltip: state.tr('上一个匹配', 'Previous match'),
                  onPressed: _matches.isEmpty
                      ? null
                      : () => _nextMatch(text, -1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: state.tr('下一个匹配', 'Next match'),
                  onPressed: _matches.isEmpty
                      ? null
                      : () => _nextMatch(text, 1),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: state.tr('关闭搜索', 'Close search'),
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        if (original != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(state.tr('尚未保留的改动', 'Unreviewed changes')),
                ),
                TextButton(
                  onPressed: () => _review(true),
                  child: Text(state.tr('保留', 'Keep')),
                ),
                TextButton(
                  onPressed: () => _review(false),
                  child: Text(state.tr('撤销', 'Undo')),
                ),
              ],
            ),
          ),
        Expanded(
          child: switch (mode) {
            _FileMode.diff => DiffView(
              before: original!,
              after: text,
              tr: state.tr,
            ),
            _FileMode.source => FileSourceView(
              text: text,
              path: widget.path,
              wrap: _wrap,
              fontSize: _fontSize,
              query: _search.text,
              activeMatchOffset: _matches.isEmpty
                  ? null
                  : _matches[_activeMatch].start,
              targetLine: _targetLine,
              navigationRevision: _navigationRevision,
            ),
            // 分段交给惰性列表：只排版看得见的块，几百行的文件滚动才跟得上。
            // 预览不做整页缩放（源码页保留），字大手写在这里调主题字号即可。
            _FileMode.preview => SelectionArea(
              child: ListView.builder(
                key: PageStorageKey(('file-preview', widget.path)),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                itemCount: preview.length,
                itemBuilder: (context, index) => Padding(
                  padding: index == 0
                      ? EdgeInsets.zero
                      : EdgeInsets.only(top: MobileTheme.markdownGap),
                  child: MarkdownBlocks(
                    nodes: preview[index],
                    style: MobileTheme.messageStyleOf(context),
                    options: MarkdownOptions(
                      colors: theme.colorScheme,
                      headingSizes: MobileTheme.headingSizesOf(context),
                      gap: MobileTheme.markdownGap,
                      inlineCodeStyle: MobileTheme.codeStyleOf(context),
                      image: _markdownImage,
                    ),
                  ),
                ),
              ),
            ),
          },
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.dividerColor, width: .5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  state.tr(
                    '只读 · ${text.split('\n').length} 行',
                    'Read only · ${text.split('\n').length} lines',
                  ),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _review(bool keep) => runUi(context, () async {
    final state = widget.state;
    final sessions = state.sessions
        .where(
          (ref) =>
              ref.desktopId == widget.project.desktopId &&
              ref.session.project == widget.project.project.id,
        )
        .toList();
    String? session = widget.sessionId;
    session ??= await showBottomSheetPanel<String>(
      context,
      title: state.tr(
        '选择产生改动的会话',
        'Choose the conversation that changed this file',
      ),
      closeLabel: state.tr('关闭', 'Close'),
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final ref in sessions)
            ListTile(
              title: Text(ref.session.title),
              onTap: () => Navigator.pop(context, ref.session.id),
            ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(state.tr('没有可操作的会话', 'No available conversation')),
            ),
        ],
      ),
    );
    if (session == null || !mounted) return;
    // Keeping harms nothing, as the tray's Keep: only undo asks.
    if (!keep &&
        !await confirmAction(
          context,
          state,
          state.tr('撤回改动？', 'Undo changes?'),
          widget.path,
          action: state.tr('撤回', 'Undo'),
          destructive: true,
        )) {
      return;
    }
    await state.request(
      widget.project.desktopId,
      keep ? LinkMethods.keep : LinkMethods.undo,
      {
        'session': session,
        'paths': [widget.path],
      },
    );
    if (mounted) setState(_load);
  });
}

class _JumpToLineDialog extends StatefulWidget {
  const _JumpToLineDialog({required this.state, required this.lineCount});
  final AppState state;
  final int lineCount;

  @override
  State<_JumpToLineDialog> createState() => _JumpToLineDialogState();
}

class _JumpToLineDialogState extends State<_JumpToLineDialog> {
  final _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final line = int.tryParse(_controller.text.trim());
    if (line == null || line < 1 || line > widget.lineCount) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, line);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.state.tr('跳到行', 'Go to line')),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.go,
      decoration: InputDecoration(
        hintText: '1–${widget.lineCount}',
        errorMaxLines: 2,
        errorText: _invalid
            ? widget.state.tr(
                '请输入 1–${widget.lineCount} 之间的行号',
                'Enter a line between 1 and ${widget.lineCount}',
              )
            : null,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: dialogButtons([
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.state.tr('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.state.tr('跳转', 'Go')),
      ),
    ]),
  );
}

/// 行宽正常时横向滚动阅读；超长行（压缩文件等）保持换行，避免生成极宽布局或截断文字。
bool _scrollsSideways(Iterable<String> lines) =>
    lines.every((line) => line.length <= 1800);

Widget _codeViewport(
  BuildContext context,
  TextStyle style,
  Iterable<String> lines,
  double gutter,
  ScrollController horizontal,
  ScrollPhysics? physics,
  Widget child,
) {
  if (!_scrollsSideways(lines)) return child;
  final longest = lines.fold<int>(
    0,
    (size, line) => line.length > size ? line.length : size,
  );
  // 保守估算宽度，不为虚拟列表预先布局每一行；宽字符也保留横向阅读空间。
  final estimate =
      longest * MediaQuery.textScalerOf(context).scale(style.fontSize!) * 1.1 +
      gutter +
      24;
  return LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      controller: horizontal,
      physics: physics,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: estimate > box.maxWidth ? estimate : box.maxWidth,
        child: child,
      ),
    ),
  );
}

class DiffView extends StatefulWidget {
  const DiffView({
    super.key,
    required this.before,
    required this.after,
    required this.tr,
  });
  final String before, after;
  final String Function(String zh, String en) tr;
  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  final _scroll = ScrollController();
  final _horizontal = ScrollController();
  // exact 为假表示视口停在 change 之后、下一处之前；change 为 -1 表示还没到第一处。
  final _at = ValueNotifier((change: 0, exact: true));
  late List<ChangedLine> _lines;
  late List<int> _starts;
  late bool _sideways;
  late TextStyle _style;
  late StrutStyle _strut;
  late TextScaler _textScaler;
  List<double> _heights = [], _offsets = [];
  Object? _layoutKey;
  bool _stepping = false;

  @override
  void initState() {
    super.initState();
    _readDiff();
    _scroll.addListener(_follow);
  }

  @override
  void didUpdateWidget(DiffView old) {
    super.didUpdateWidget(old);
    if (old.before != widget.before || old.after != widget.after) _readDiff();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _horizontal.dispose();
    _at.dispose();
    super.dispose();
  }

  void _readDiff() {
    _lines = lineDiff(widget.before, widget.after);
    _starts = changeStarts(_lines);
    _sideways = _scrollsSideways(_lines.map((line) => line.text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _go(0);
    });
  }

  // 行高事先算好，才能直接跳到虚拟列表里还没构建的行。
  void _layout(BuildContext context, double width) {
    final style = MobileTheme.codeStyleOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final key = (_lines, style, scaler, _sideways ? null : width);
    if (key == _layoutKey) return;
    _layoutKey = key;
    _style = style;
    _textScaler = scaler;
    _strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final sample = _painter('Mg')..layout();
    final lineHeight = sample.height;
    sample.dispose();
    _heights = [
      for (final line in _lines)
        if (_sideways) lineHeight else _wrappedHeight(line.text, width),
    ];
    _offsets = [0];
    for (final height in _heights) {
      _offsets.add(_offsets.last + height);
    }
  }

  TextPainter _painter(String text) => TextPainter(
    text: TextSpan(text: text.isEmpty ? ' ' : text, style: _style),
    textDirection: TextDirection.ltr,
    textScaler: _textScaler,
    strutStyle: _strut,
  );

  double _wrappedHeight(String text, double width) {
    final painter = _painter(text)..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  // 改动落在视口上方约 1/5 处，上文也能看到一点。
  double _stop(int change) {
    final position = _scroll.position;
    return (_offsets[_starts[change]] - position.viewportDimension * .2).clamp(
      0.0,
      position.maxScrollExtent,
    );
  }

  void _go(int change) {
    if (!_scroll.hasClients || change < 0 || change >= _starts.length) return;
    _stepping = true;
    _scroll.jumpTo(_stop(change));
    _stepping = false;
    _at.value = (change: change, exact: true);
  }

  // 文件末尾几处改动的落点会重合，所以按钮跳转时不从位置反推序号。
  void _follow() {
    if (_stepping || _starts.isEmpty) return;
    final pixels = _scroll.position.pixels;
    var change = -1;
    while (change + 1 < _starts.length && _stop(change + 1) <= pixels + 1) {
      change++;
    }
    _at.value = (
      change: change,
      exact: change >= 0 && (_stop(change) - pixels).abs() <= 1,
    );
  }

  void _step(int delta) {
    final at = _at.value;
    _go(delta < 0 && !at.exact ? at.change : at.change + delta);
  }

  Widget _changeBar(BuildContext context) => ValueListenableBuilder(
    valueListenable: _at,
    builder: (context, at, _) => ChangeNavigationBar(
      at: (at: at.change, exact: at.exact),
      total: _starts.length,
      onStep: _step,
      tr: widget.tr,
      keyPrefix: 'diff',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final count =
        widget.before.split('\n').length > widget.after.split('\n').length
        ? widget.before.split('\n').length
        : widget.after.split('\n').length;
    final metrics = diffLineMetrics(context, count);
    final style = metrics.style;
    final gutter = metrics.gutter, marker = metrics.marker;
    // One number column, as on phones: a removed line has its number from
    // before, every other line its number now; the colour and the sign tell
    // them apart.
    return Stack(
      fit: StackFit.expand,
      children: [
        PageZoom(
          vertical: _scroll,
          horizontal: _horizontal,
          builder: (context, physics, scale) => LayoutBuilder(
            builder: (context, box) {
              _layout(
                context,
                (box.maxWidth - gutter - marker - 16).clamp(
                  1.0,
                  double.infinity,
                ),
              );
              return SelectionArea(
                child: _codeViewport(
                  context,
                  style,
                  lines.map((line) => line.text),
                  gutter + marker + 24,
                  _horizontal,
                  physics,
                  ListView.custom(
                    controller: _scroll,
                    physics: physics,
                    // 留出浮动按钮的高度，最后几行不被盖住；按钮不随页面缩放。
                    padding: EdgeInsets.only(
                      bottom: _starts.isEmpty ? 0 : 72 / scale,
                    ),
                    semanticChildCount: lines.length,
                    itemExtentBuilder: (index, _) => _heights[index],
                    childrenDelegate: _KnownExtentDelegate(
                      (context, index) => DiffLineRow(
                        lines[index],
                        metrics: metrics,
                        strutStyle: _strut,
                        softWrap: !_sideways,
                      ),
                      childCount: lines.length,
                      extent: _offsets.last,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_starts.isNotEmpty)
          Positioned(right: 12, bottom: 12, child: _changeBar(context)),
      ],
    );
  }
}

/// 超长行夹在中间时，按已构建的行外推会把总高度算短，跳不到后面的改动。
class _KnownExtentDelegate extends SliverChildBuilderDelegate {
  const _KnownExtentDelegate(
    super.builder, {
    super.childCount,
    required this.extent,
  });
  final double extent;
  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => extent;
}

/// `~/Desktop/app` for a path in a home folder (`/Users/<name>`,
/// `/home/<name>`, `C:\Users\<name>`); other paths as they are.
String shortPath(String path) {
  final home = RegExp(
    r'^(/Users/[^/]+|/home/[^/]+|[A-Za-z]:\\Users\\[^\\]+)(?=$|[/\\])',
  );
  final match = home.firstMatch(path);
  return match == null ? path : '~${path.substring(match.end)}';
}

/// One line per entry, every row the same height: the icon in a fixed box,
/// the name (its extension kept when it is cut), and on the right a folder's
/// count or a changed file's Git letter.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.directory,
    required this.tr,
    required this.onTap,
    this.count,
    this.change,
    this.ignored = false,
  });

  final String name;
  final bool directory, ignored;
  final int? count;
  final String? change;
  final String Function(String zh, String en) tr;
  final VoidCallback onTap;

  static const _iconBox = 22.0;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final status = MobileTheme.statusColorsOf(context);
    final aside = TextStyle(color: hint, fontSize: MobileType.aside);
    final dot = name.lastIndexOf('.');
    final (stem, extension) = !directory && dot > 0
        ? (name.substring(0, dot), name.substring(dot))
        : (name, '');
    final (letter, tone) = switch (change) {
      'added' => ('A', status.added),
      'modified' => ('M', status.warning),
      _ => (null, null),
    };
    return InkWell(
      key: ValueKey('file-row-$name'),
      onTap: onTap,
      child: Opacity(
        opacity: ignored ? _ignoredOpacity : 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: _iconBox,
                  child: Center(
                    child: directory
                        ? material_icons.FolderIcon(name, size: _iconBox)
                        : material_icons.FileIcon(name, size: _iconBox),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final style = Theme.of(context).textTheme.bodyLarge;
                      final full = TextPainter(
                        text: TextSpan(text: name, style: style),
                        maxLines: 1,
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      final fits = full.width <= constraints.maxWidth;
                      full.dispose();
                      if (fits || extension.isEmpty) {
                        return Text(
                          name,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      }
                      return Semantics(
                        label: name,
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  stem,
                                  style: style,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(extension, style: style, maxLines: 1),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 12),
                  Text('$count ${tr('项', 'items')}', style: aside),
                ],
                if (letter != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    letter,
                    style: aside.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (directory) ...[
                  const SizedBox(width: 4),
                  LucideIcon('chevron-right', size: 16, color: hint),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
