import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NookApp());

const _ink = Color(0xFF202938);
const _muted = Color(0xFF758195);
const _blue = Color(0xFF6C9ED4);
const _canvas = Color(0xFFF0F5FB);
const _line = Color(0xFFE5EBF2);
const _surfaceShadow = Color(0x127A9CC4);

class NookApp extends StatelessWidget {
  const NookApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nook',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _blue,
        brightness: Brightness.light,
      ),
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: _ink,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: _ink,
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: _ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: _ink, fontSize: 14),
        bodySmall: TextStyle(color: _muted, fontSize: 12),
      ),
    ),
    home: const NookHome(),
  );
}

class LocalEntry {
  const LocalEntry({
    required this.title,
    required this.detail,
    required this.createdAt,
    this.amountCents = 0,
    this.isIncome = false,
  });

  final String title;
  final String detail;
  final DateTime createdAt;
  final int amountCents;
  final bool isIncome;

  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'createdAt': createdAt.toIso8601String(),
    'amountCents': amountCents,
    'isIncome': isIncome,
  };

  factory LocalEntry.fromJson(Map<String, dynamic> json) => LocalEntry(
    title: json['title'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    amountCents: json['amountCents'] as int? ?? 0,
    isIncome: json['isIncome'] as bool? ?? false,
  );
}

class NookHome extends StatefulWidget {
  const NookHome({super.key});

  @override
  State<NookHome> createState() => _NookHomeState();
}

class _NookHomeState extends State<NookHome> {
  static const _storeKey = 'nook.local.entries.v1';
  final List<LocalEntry> _notes = [];
  final List<LocalEntry> _events = [];
  final List<LocalEntry> _transactions = [];
  int _tab = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storeKey);
    if (!mounted) return;
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _notes.addAll(_decodeList(decoded['notes']));
        _events.addAll(_decodeList(decoded['events']));
        _transactions.addAll(_decodeList(decoded['transactions']));
      } on FormatException {
        // Leave a damaged local cache untouched so it can be recovered manually.
      } on TypeError {
        // Ignore incompatible cache versions instead of crashing at launch.
      }
    }
    setState(() => _loaded = true);
  }

  List<LocalEntry> _decodeList(Object? value) {
    if (value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(LocalEntry.fromJson)
        .toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storeKey,
      jsonEncode({
        'notes': _notes.map((item) => item.toJson()).toList(),
        'events': _events.map((item) => item.toJson()).toList(),
        'transactions': _transactions.map((item) => item.toJson()).toList(),
      }),
    );
  }

  Future<void> _addEntry(String kind) async {
    final entry = await showModalBottomSheet<LocalEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EntryEditor(kind: kind),
    );
    if (entry == null) return;
    setState(() {
      switch (kind) {
        case 'note':
          _notes.insert(0, entry);
        case 'event':
          _events.insert(0, entry);
        case 'transaction':
          _transactions.insert(0, entry);
      }
    });
    await _save();
  }

  Future<void> _deleteEntry(String kind, LocalEntry entry) async {
    setState(() {
      switch (kind) {
        case 'note':
          _notes.remove(entry);
        case 'event':
          _events.remove(entry);
        case 'transaction':
          _transactions.remove(entry);
      }
    });
    await _save();
  }

  void _selectTab(int index) => setState(() => _tab = index);

  @override
  Widget build(BuildContext context) {
    final titles = ['今天', '便签', '密码库', '日程', '记账'];
    final pages = [
      _dashboard(),
      _entryList('note'),
      _vaultPage(),
      _entryList('event'),
      _entryList('transaction'),
    ];
    return Scaffold(
      body: SafeArea(
        child: _tab == 0
            ? Column(
                children: [
                  _HomeHero(date: DateTime.now()),
                  Expanded(
                    child: !_loaded
                        ? const Center(child: CircularProgressIndicator())
                        : _dashboard(),
                  ),
                  _BottomNavigation(selected: _tab, onSelect: _selectTab),
                ],
              )
            : Column(
                children: [
                  _TopBar(
                    title: titles[_tab],
                    onAdd: _tab == 2
                        ? null
                        : () => _addEntry(_kindForTab(_tab)),
                  ),
                  Expanded(
                    child: !_loaded
                        ? const Center(child: CircularProgressIndicator())
                        : IndexedStack(index: _tab, children: pages),
                  ),
                  _BottomNavigation(selected: _tab, onSelect: _selectTab),
                ],
              ),
      ),
    );
  }

  String _kindForTab(int tab) => switch (tab) {
    1 => 'note',
    3 => 'event',
    4 => 'transaction',
    _ => 'note',
  };

  Widget _dashboard() {
    final today = DateTime.now();
    final monthOut = _transactions
        .where(
          (e) =>
              !e.isIncome &&
              e.createdAt.year == today.year &&
              e.createdAt.month == today.month,
        )
        .fold<int>(0, (sum, e) => sum + e.amountCents);
    final upcoming = _events
        .where(
          (e) => e.createdAt.isAfter(
            DateTime.now().subtract(const Duration(hours: 1)),
          ),
        )
        .take(3)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      children: [
        _DateRow(date: today),
        const SizedBox(height: 12),
        _SectionHeading(
          title: '即将到来',
          action: '全部',
          onTap: () => _selectTab(3),
        ),
        const SizedBox(height: 7),
        _Panel(
          child: upcoming.isEmpty
              ? Column(
                  children: [
                    _TimelineRow(
                      entry: LocalEntry(
                        title: '今天还没有安排',
                        detail: '',
                        createdAt: DateTime(
                          today.year,
                          today.month,
                          today.day,
                          10,
                        ),
                      ),
                      last: true,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _addEntry('event'),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('添加日程'),
                        style: TextButton.styleFrom(foregroundColor: _blue),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (var i = 0; i < upcoming.length; i++)
                      _TimelineRow(
                        entry: upcoming[i],
                        last: i == upcoming.length - 1,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _SectionHeading(
          title: '最近便签',
          action: '查看全部',
          onTap: () => _selectTab(1),
        ),
        const SizedBox(height: 7),
        if (_notes.isEmpty)
          _Panel(
            child: _EmptyLine(
              icon: Icons.edit_note_rounded,
              text: '还没有便签',
              action: '记下一个想法',
              onTap: () => _addEntry('note'),
            ),
          )
        else
          _Panel(
            child: _EntryTile(
              entry: _notes.first,
              icon: Icons.sticky_note_2_outlined,
              tint: const Color(0xFFEAF2FC),
              onDelete: () => _deleteEntry('note', _notes.first),
            ),
          ),
        const SizedBox(height: 12),
        _SectionHeading(
          title: '本月支出',
          action: '明细',
          onTap: () => _selectTab(4),
        ),
        const SizedBox(height: 7),
        _SpendPanel(
          amount: monthOut,
          count: _transactions.where((e) => !e.isIncome).length,
        ),
        const SizedBox(height: 12),
        _SectionHeading(
          title: '我的密码库',
          action: '查看',
          onTap: () => _selectTab(2),
        ),
        const SizedBox(height: 7),
        _VaultSummary(onTap: () => _selectTab(2)),
      ],
    );
  }

  Widget _entryList(String kind) {
    final (items, icon, empty, description) = switch (kind) {
      'note' => (_notes, Icons.sticky_note_2_outlined, '还没有便签', '随手记下灵感、计划和待办'),
      'event' => (_events, Icons.event_outlined, '日程还空着', '把重要安排放进 Nook'),
      _ => (
        _transactions,
        Icons.account_balance_wallet_outlined,
        '还没有收支记录',
        '从第一笔开始了解每月开销',
      ),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      children: [
        if (kind == 'transaction')
          _FinanceSummary(items: items)
        else
          _ListSummary(
            label: kind == 'note' ? '全部便签' : '所有安排',
            count: items.length,
            subtitle: kind == 'note' ? '本地保存' : '本地日程',
          ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          _Panel(
            child: _EmptyLine(
              icon: icon,
              text: empty,
              action: description,
              onTap: () => _addEntry(kind),
            ),
          )
        else
          _Panel(
            child: Column(
              children: [
                for (final entry in items)
                  _EntryTile(
                    entry: entry,
                    icon: icon,
                    tint: _tint(kind),
                    onDelete: () => _deleteEntry(kind, entry),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _vaultPage() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
    children: [
      Text(
        '密码库尚未开放；当前版本请勿保存密码或恢复码。',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 14),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE5F5EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFF55A981),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '密码库正在准备中',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '我们会先完成本地数据与安全基础，再开放账号和密码保存。',
              style: TextStyle(color: _muted, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _Panel(
        child: Column(
          children: const [
            _VaultRow(icon: Icons.key_outlined, label: '网站账号', value: '稍后开放'),
            _VaultRow(
              icon: Icons.credit_card_outlined,
              label: '银行卡',
              value: '稍后开放',
            ),
            _VaultRow(
              icon: Icons.note_alt_outlined,
              label: '安全笔记',
              value: '稍后开放',
            ),
          ],
        ),
      ),
    ],
  );

  Color _tint(String kind) => switch (kind) {
    'note' => const Color(0xFFEAF2FC),
    'event' => const Color(0xFFE8F5F0),
    _ => const Color(0xFFFFF0E7),
  };
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, required this.kind});
  final String kind;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _title = TextEditingController();
  final _detail = TextEditingController();
  final _amount = TextEditingController();
  bool _income = false;
  DateTime _when = DateTime.now();

  String get _label => switch (widget.kind) {
    'note' => '便签',
    'event' => '日程',
    _ => '收支记录',
  };

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTransaction = widget.kind == 'transaction';
    final isEvent = widget.kind == 'event';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '新建$_label',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isTransaction) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('支出'),
                      icon: Icon(Icons.north_east_rounded),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('收入'),
                      icon: Icon(Icons.south_west_rounded),
                    ),
                  ],
                  selected: {_income},
                  onSelectionChanged: (value) =>
                      setState(() => _income = value.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '¥ ',
                    labelText: '金额',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: isEvent
                      ? '安排名称'
                      : isTransaction
                      ? '分类或商家'
                      : '标题',
                  hintText: isEvent
                      ? '例如：和朋友吃晚餐'
                      : isTransaction
                      ? '例如：餐饮'
                      : '写下一个想法',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detail,
                maxLines: isEvent ? 2 : 4,
                decoration: InputDecoration(
                  labelText: isEvent ? '备注' : '内容',
                  alignLabelWithHint: true,
                ),
              ),
              if (isEvent) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _chooseDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    '${_when.month}月${_when.day}日  ${_timeLabel(_when)}',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (time == null) return;
    setState(
      () => _when = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (widget.kind == 'transaction' && (amount == null || amount <= 0)) return;
    Navigator.pop(
      context,
      LocalEntry(
        title: title,
        detail: _detail.text.trim(),
        createdAt: widget.kind == 'event' ? _when : DateTime.now(),
        amountCents: ((amount ?? 0) * 100).round(),
        isIncome: _income,
      ),
    );
  }

  String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onAdd});
  final String title;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 18, 12),
    child: Row(
      children: [
        Container(
          width: 33,
          height: 33,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _line),
          ),
          child: const Icon(Icons.check_rounded, color: _blue, size: 21),
        ),
        const SizedBox(width: 10),
        Text(
          'Nook',
          style: TextStyle(
            color: _muted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 10),
        if (onAdd != null)
          IconButton.filledTonal(
            key: const ValueKey('create-entry'),
            onPressed: onAdd,
            tooltip: '新建',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _ink,
              fixedSize: const Size(40, 40),
            ),
            icon: const Icon(Icons.add_rounded, size: 22),
          ),
      ],
    ),
  );
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final greeting = date.hour < 12
        ? '早上好'
        : date.hour < 18
        ? '下午好'
        : '晚上好';
    return SizedBox(
      height: 156,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _HeroWavePainter()),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .85),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: _blue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      'Nook',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      tooltip: '通知',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .82),
                        fixedSize: const Size(38, 38),
                      ),
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: _ink,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFFDDEBFA),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: _blue,
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  greeting,
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 1),
                const Text(
                  '今天',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xFFE8F2FD);
    final wave = Paint()..color = const Color(0xFFD8E9FB);
    final second = Paint()
      ..color = const Color(0xFFD1E4F9).withValues(alpha: .58);
    canvas.drawRect(Offset.zero & size, base);
    final path = Path()
      ..moveTo(0, size.height * .73)
      ..cubicTo(
        size.width * .28,
        size.height * .58,
        size.width * .43,
        size.height * .98,
        size.width * .7,
        size.height * .76,
      )
      ..cubicTo(
        size.width * .84,
        size.height * .64,
        size.width * .92,
        size.height * .63,
        size.width,
        size.height * .67,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, wave);
    final lower = Path()
      ..moveTo(0, size.height * .88)
      ..cubicTo(
        size.width * .25,
        size.height * .78,
        size.width * .42,
        size.height * 1.02,
        size.width * .72,
        size.height * .89,
      )
      ..cubicTo(
        size.width * .86,
        size.height * .82,
        size.width * .94,
        size.height * .83,
        size.width,
        size.height * .87,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(lower, second);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 5, 4, 1),
    child: Row(
      children: [
        const Icon(Icons.calendar_today_outlined, size: 19, color: _ink),
        const SizedBox(width: 10),
        Text(
          '${_weekdayName(date.weekday)}，${date.month}月${date.day}日',
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: _muted),
        const Spacer(),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            foregroundColor: _muted,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('今天'),
        ),
      ],
    ),
  );
}

class _VaultSummary extends StatelessWidget {
  const _VaultSummary({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFE5F5EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFF55A981),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '密码库',
                    style: TextStyle(fontWeight: FontWeight.w600, color: _ink),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '本地安全功能即将开放',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 19),
          ],
        ),
      ),
    ),
  );
}

String _weekdayName(int day) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day - 1];

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, '首页'),
    (Icons.edit_note_outlined, Icons.edit_note_rounded, '便签'),
    (Icons.lock_outline_rounded, Icons.lock_rounded, '密码库'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, '日程'),
    (Icons.query_stats_outlined, Icons.query_stats_rounded, '记账'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE8EEF5)),
      boxShadow: const [
        BoxShadow(color: _surfaceShadow, blurRadius: 18, offset: Offset(0, 5)),
      ],
    ),
    child: Row(
      children: [
        for (var i = 0; i < _items.length; i++)
          Expanded(
            child: _NavButton(
              index: i,
              selected: selected == i,
              item: _items[i],
              onTap: () => onSelect(i),
            ),
          ),
      ],
    ),
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.index,
    required this.selected,
    required this.item,
    required this.onTap,
  });
  final int index;
  final bool selected;
  final (IconData, IconData, String) item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.$3,
    excludeSemantics: true,
    child: InkWell(
      key: ValueKey('nav-$index'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 46,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: selected
                  ? (index == 0
                        ? const Color(0xFF3A4655)
                        : const Color(0xFFD9EBFF))
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              selected ? item.$2 : item.$1,
              color: selected ? (index == 0 ? Colors.white : _blue) : _muted,
              size: 21,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.action,
    required this.onTap,
  });
  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const Spacer(),
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: _muted,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(action),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .97),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEDF2F7)),
      boxShadow: const [
        BoxShadow(color: _surfaceShadow, blurRadius: 14, offset: Offset(0, 4)),
      ],
    ),
    child: child,
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.last});
  final LocalEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 12),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF73C8A7),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 11),
        Text(
          _time(entry.createdAt),
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
          ),
        ),
        if (entry.detail.isNotEmpty)
          const Icon(Icons.chevron_right_rounded, size: 18, color: _muted),
      ],
    ),
  );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.icon,
    required this.tint,
    required this.onDelete,
  });
  final LocalEntry entry;
  final IconData icon;
  final Color tint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ObjectKey(entry),
    direction: DismissDirection.endToStart,
    onDismissed: (_) => onDelete(),
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 18),
      color: const Color(0xFFFFE6E2),
      child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFC45E55)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _blue, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      entry.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  entry.amountCents > 0
                      ? '${entry.isIncome ? '+' : '-'}¥${(entry.amountCents / 100).toStringAsFixed(2)} · ${_date(entry.createdAt)}'
                      : _date(entry.createdAt),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({
    required this.icon,
    required this.text,
    this.action,
    this.onTap,
  });
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: Color(0xFFF2F6FA),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _blue, size: 19),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
            ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  action!,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      if (onTap != null)
        IconButton(
          onPressed: onTap,
          tooltip: '新建',
          icon: const Icon(Icons.add_rounded, color: _muted),
        ),
    ],
  );
}

class _SpendPanel extends StatelessWidget {
  const _SpendPanel({required this.amount, required this.count});
  final int amount;
  final int count;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFFE5F5EC),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.account_balance_wallet_outlined,
            color: Color(0xFF4FA97E),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¥${(amount / 100).toStringAsFixed(2)}',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '本月支出 · $count 笔',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 74,
          height: 42,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _MiniBar(height: 14),
              _MiniBar(height: 24),
              _MiniBar(height: 18),
              _MiniBar(height: 32, strong: true),
              _MiniBar(height: 25),
              _MiniBar(height: 17),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.height, this.strong = false});
  final double height;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: height,
    decoration: BoxDecoration(
      color: strong ? const Color(0xFF83D8AE) : const Color(0xFFC9EFDD),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

class _ListSummary extends StatelessWidget {
  const _ListSummary({
    required this.label,
    required this.count,
    required this.subtitle,
  });
  final String label;
  final int count;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _ink,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      const Spacer(),
      Text(
        '$count 项  ·  $subtitle',
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
    ],
  );
}

class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({required this.items});
  final List<LocalEntry> items;

  @override
  Widget build(BuildContext context) {
    final expenses = items
        .where((e) => !e.isIncome)
        .fold<int>(0, (sum, e) => sum + e.amountCents);
    final incomes = items
        .where((e) => e.isIncome)
        .fold<int>(0, (sum, e) => sum + e.amountCents);
    return _Panel(
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: '支出',
              amount: expenses,
              color: const Color(0xFFC7795B),
            ),
          ),
          Container(width: 1, height: 38, color: _line),
          Expanded(
            child: _Metric(
              label: '收入',
              amount: incomes,
              color: const Color(0xFF4F9B7B),
            ),
          ),
          Container(width: 1, height: 38, color: _line),
          Expanded(
            child: _Metric(label: '记录', count: items.length, color: _blue),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.color,
    this.amount,
    this.count,
  });
  final String label;
  final Color color;
  final int? amount;
  final int? count;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      const SizedBox(height: 5),
      Text(
        amount != null ? '¥${(amount! / 100).toStringAsFixed(0)}' : '$count',
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _VaultRow extends StatelessWidget {
  const _VaultRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: _blue, size: 19),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
          ),
        ),
        Text(value, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    ),
  );
}

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _date(DateTime value) => '${value.month}月${value.day}日';
