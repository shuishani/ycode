// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

/// 模型、模式这些选项的展示和选择。
extension _Choices on _ChatPageState {
  Future<void> _choices(BuildContext anchor, LinkChoice choice) async {
    // 打开设置弹层不动键盘：开着就让它开着，关掉后还是原样。
    if (!_hasSession) return;
    final session = _sessionId;
    final generation = _binding.generation;
    final identity = _binding.identity;
    bool current() =>
        mounted &&
        _binding.available &&
        _online &&
        _binding.generation == generation &&
        _sessionId == session;
    // 设置弹层开着的时候可能断线重连：那还是同一个会话，不该因此关掉。
    // 在线与否由弹层自己的 ready 判断。
    bool sameConversation() =>
        mounted &&
        _binding.available &&
        _binding.identity == identity &&
        _sessionId == session;
    if (choice.kind == 'model') {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        requestFocus: false,
        builder: (_) => ModelSettingsSheet(
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: session,
          isCurrent: sameConversation,
        ),
      );
      return;
    }
    // `fast` is the desktop's toggle setting (SelectsFast): the wire carries
    // no toggle flag, and its one option flips it on each choose — no menu.
    if (choice.kind == 'fast' && choice.options.isNotEmpty) {
      await _command(LinkMethods.choose, {
        'kind': 'fast',
        'option': choice.options.first.id,
      });
      return;
    }
    final option = await showDropdownPanel<String>(
      anchor,
      width: 640,
      requestFocus: false,
      builder: (context) {
        final options = choice.options;
        final groups = <String>{};
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      choice.kind == 'permission'
                          ? tr('应如何获得批准？', 'How should actions be approved?')
                          : _choiceLabel(choice.kind),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                // The tiles' own 16 lines their icons up with the title.
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  for (final option in options) ...[
                    if ((option.groupLabel ?? option.group)
                        case final String group
                        when group.isNotEmpty && groups.add(group))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                        child: Text(
                          group,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ListTile(
                      horizontalTitleGap: 12,
                      leading:
                          _choicePresentation(choice.kind, option).$3 == null
                          ? null
                          : LucideIcon(
                              _choicePresentation(choice.kind, option).$3!,
                              size: _opticalIconSize(
                                _choicePresentation(choice.kind, option).$3!,
                                22,
                              ),
                              color: option.caution
                                  ? MobileTheme.statusColorsOf(context).warning
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                            ),
                      selectedColor: Theme.of(context).colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(MobileSizes.radius),
                      ),
                      selected: choice.selected == option.id,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      title: Text(_choicePresentation(choice.kind, option).$1),
                      subtitle:
                          _choicePresentation(choice.kind, option).$2.isEmpty
                          ? null
                          : Text(_choicePresentation(choice.kind, option).$2),
                      trailing: choice.selected == option.id
                          ? LucideIcon(
                              'check',
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, option.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
    if (!mounted || option == null) return;
    if (!current()) {
      if (mounted) {
        setState(
          () => _error = tr(
            '会话已变化，请重新选择设置。',
            'Conversation changed. Choose the setting again.',
          ),
        );
      }
      return;
    }
    await _command(LinkMethods.choose, {'kind': choice.kind, 'option': option});
  }

  (String, String, String?) _choicePresentation(
    String kind,
    LinkOption option,
  ) => switch ((kind, option.id)) {
    ('mode', 'agent') => (
      option.label,
      tr('规划、编辑并运行代码', option.description),
      'infinity',
    ),
    ('mode', 'ask') => (
      option.label,
      tr('只讨论和解答，给出改动建议', option.description),
      'message-circle',
    ),
    ('mode', 'plan') => (
      option.label,
      tr('先调研和制定计划，再动手', option.description),
      'list-checks',
    ),
    ('permission', 'default') => (
      tr('逐项批准', option.label),
      tr('编辑和命令前都先询问', option.description),
      'shield',
    ),
    ('permission', 'acceptEdits') => (
      tr('自动接受编辑', option.label),
      tr('直接编辑文件，运行命令前询问', option.description),
      'file-pen',
    ),
    ('permission', 'auto') => (
      tr('替我批准', option.label),
      tr('安全的自动通过，有风险的拦下', option.description),
      'shield-check',
    ),
    ('permission', 'dontAsk') => (
      tr('仅限已允许', option.label),
      tr('未预先允许的一律拒绝', option.description),
      'ban',
    ),
    ('permission', 'bypassPermissions') => (
      tr('完全访问', option.label),
      tr('不做任何检查，编辑和命令直接执行', option.description),
      'shield-alert',
    ),
    _ => (option.label, option.description, null),
  };

  /// ∞ 只占画布中间一窄条，同尺寸时显得比盾牌等图标小，略放大补偿。
  double _opticalIconSize(String name, double size) =>
      name == 'infinity' ? size + 2 : size;

  String _choiceLabel(String kind) => switch (kind) {
    'model' => tr('模型', 'Model'),
    'mode' => tr('模式', 'Mode'),
    'permission' => tr('权限', 'Permissions'),
    'effort' => tr('推理强度', 'Effort'),
    'context' => tr('上下文', 'Context'),
    'fast' => tr('快速', 'Fast'),
    _ => kind,
  };

  /// The value after the chip's colon. Toggle kinds (the wire carries no
  /// toggle flag; desktop `SelectsFast` is the one) read 开/关 — their off
  /// state has no option to name, so the raw `selected` would show `—`.
  String _chipValue(LinkChoice choice) => switch (choice.kind) {
    'fast' => choice.selected == 'fast' ? tr('开', 'On') : tr('关', 'Off'),
    _ => _selectedLabel(choice),
  };

  String _selectedLabel(LinkChoice choice) {
    for (final option in choice.options) {
      if (option.id == choice.selected) {
        return _choicePresentation(choice.kind, option).$1;
      }
    }
    return choice.selected ?? '—';
  }

  List<LinkChoice> _visibleChoices(SessionBuffer buffer) {
    final hasModel = buffer.choices.any((entry) => entry.kind == 'model');
    return [
      for (final choice in buffer.choices)
        if (!hasModel || !{'context', 'effort', 'fast'}.contains(choice.kind))
          choice,
    ];
  }

  bool _iconOnly(LinkChoice choice) =>
      choice.kind == 'mode' ||
      choice.kind == 'permission' ||
      choice.kind == 'model';

  /// Mode, permission, model, then anything else: all icon buttons.
  List<LinkChoice> _composerChoices(SessionBuffer buffer) {
    final choices = _visibleChoices(buffer);
    int rank(LinkChoice choice) => switch (choice.kind) {
      'mode' => 0,
      'permission' => 1,
      'model' => 2,
      _ => 3,
    };
    return [...choices]..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  bool get _fastOn => _buffer.choices.any(
    (choice) => choice.kind == 'fast' && choice.selected == 'fast',
  );

  String _choiceTooltip(LinkChoice choice) {
    final contextLabel = choice.kind == 'model' ? _contextLabel : null;
    return '${_choiceLabel(choice.kind)}: ${_chipValue(choice)}'
        '${contextLabel == null ? '' : ' · ${_choiceLabel('context')} $contextLabel'}';
  }

  Widget _choiceIconButton(LinkChoice choice, bool ready) {
    final enabled = ready && !_commandBusy;
    final scheme = Theme.of(context).colorScheme;
    final color = enabled
        ? scheme.onSurfaceVariant
        : scheme.onSurfaceVariant.withValues(alpha: .5);
    final icon = _choiceIcon(choice, color, 20);
    return Builder(
      builder: (anchor) => IconButton(
        tooltip: _choiceTooltip(choice),
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? () => _choices(anchor, choice) : null,
        icon: choice.kind == 'model' && _fastOn
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  icon,
                  Positioned(
                    right: -5,
                    top: -4,
                    child: LucideIcon(
                      'zap',
                      key: const ValueKey('model-fast-badge'),
                      size: 11,
                      color: MobileTheme.statusColorsOf(context).warning,
                    ),
                  ),
                ],
              )
            : icon,
      ),
    );
  }

  /// 当前这一档模型的 logo：和电脑端 chip 上的那个一样，认不出厂商就画上游的，
  /// 都认不出才是一个脑子。
  Widget _selectedModelIcon(Color color, double size) {
    final choice = _buffer.choices
        .where((item) => item.kind == 'model')
        .firstOrNull;
    final selected = choice?.options
        .where((option) => option.id == choice.selected)
        .firstOrNull;
    if (selected == null) return LucideIcon('brain', size: size, color: color);
    return ModelIcon.ofId(
      selected.id,
      provider: selected.group,
      providerLabel: selected.groupLabel,
      size: size,
      color: color,
    );
  }

  Widget _choiceIcon(LinkChoice choice, Color color, [double size = 18]) {
    if (choice.kind == 'model') return _selectedModelIcon(color, size);
    final selected = choice.options
        .where((option) => option.id == choice.selected)
        .firstOrNull;
    final name = selected == null
        ? null
        : _choicePresentation(choice.kind, selected).$3;
    if (name == null && !_iconOnly(choice)) {
      return Icon(Icons.tune, size: size, color: color);
    }
    final icon =
        name ??
        switch (choice.kind) {
          'permission' => 'shield',
          _ => 'infinity',
        };
    return LucideIcon(
      icon,
      size: _opticalIconSize(icon, size),
      color: choice.kind == 'permission' && selected?.id == 'bypassPermissions'
          ? MobileTheme.statusColorsOf(context).warning
          : color,
    );
  }

  String? get _contextLabel {
    final choice = _buffer.choices
        .where((item) => item.kind == 'context')
        .firstOrNull;
    final label = choice?.options
        .where((option) => option.id == choice.selected)
        .firstOrNull
        ?.label
        .trim();
    return label == null || label.isEmpty ? null : label;
  }
}
