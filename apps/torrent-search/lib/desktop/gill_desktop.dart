// Torrent Search Engine on Gill(OS): the same app as on iPhone, laid out for a PC or handheld
// screen with Gill(OS)'s Liquid Glass look.
//
//  - A glass sidebar (Search, Saved, Settings) instead of the iPhone tab bar; it folds to icons on
//    small screens (handhelds), and the content stays a comfortable reading width on big ones.
//  - Gill(OS) window buttons on the right (green, yellow, red) with symbols on hover, the same as
//    every other Gill(OS) window; they grow for fingers after the screen is touched.
//  - The accent colour (and AMOLED black) follow Gill(OS) Settings > Appearance, live.
//  - Keyboard: Ctrl+F or / to search, Ctrl+1/2/3 to switch, Esc to leave the search field.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../appearance.dart';
import '../main.dart';
import '../screens/favourites_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';

/// Gill(OS) Settings > Appearance, read from ~/.config/gill-osaab/appearance.json and followed live.
class GillSystem extends ChangeNotifier {
  GillSystem._();
  static final instance = GillSystem._();

  Color accent = const Color(0xFF0A84FF);
  bool amoled = false;
  Timer? _timer;
  DateTime? _modified;

  File get _file => File('${Platform.environment['HOME'] ?? ''}/.config/gill-osaab/appearance.json');

  void start() {
    _read();
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _read());
  }

  void _read() {
    try {
      final f = _file;
      if (!f.existsSync()) return;
      final m = f.lastModifiedSync();
      if (m == _modified) return;
      _modified = m;
      final data = jsonDecode(f.readAsStringSync());
      if (data is! Map) return;
      final a = data['accent'];
      if (a is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(a)) {
        accent = Color(int.parse(a.substring(1), radix: 16) | 0xFF000000);
      }
      amoled = data['amoled'] == true;
      notifyListeners();
    } catch (_) {
      // a half-written file: try again next time
    }
  }
}

/// The window: drag, minimise, zoom, full screen, close (native side: linux/runner).
class GillWindow {
  static const _channel = MethodChannel('gill/window');
  static Future<void> call(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {}
  }
}

class GillDesktopApp extends StatelessWidget {
  const GillDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, GillSystem.instance]),
      builder: (context, _) {
        final sys = GillSystem.instance;
        final base = buildTheme(sys.accent);
        return MaterialApp(
          title: 'Torrent Search Engine',
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: sys.amoled ? Colors.black : const Color(0xFF1C1C1E),
            appBarTheme: base.appBarTheme.copyWith(backgroundColor: Colors.transparent),
            scrollbarTheme: ScrollbarThemeData(
              thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.25)),
              radius: const Radius.circular(8),
              thickness: const WidgetStatePropertyAll(6),
            ),
          ),
          home: const DesktopShell(),
        );
      },
    );
  }
}

class _Tab {
  final IconData icon;
  final String label;
  const _Tab(this.icon, this.label);
}

const _tabs = [
  _Tab(CupertinoIcons.search, 'Search'),
  _Tab(CupertinoIcons.bookmark_fill, 'Saved'),
  _Tab(CupertinoIcons.gear_solid, 'Settings'),
];

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _tab = 0;
  DateTime _lastTouch = DateTime(2000);

  /// Fingers on the screen in the last 10 minutes: bigger window buttons (like the rest of Gill(OS)).
  bool get _touchMode => DateTime.now().difference(_lastTouch) < const Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _typing => FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  /// Keyboard shortcuts, wherever the focus is: Ctrl+F or / search, Ctrl+1/2/3 switch, Ctrl+Q quit.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyF) {
      _focusSearch();
    } else if (ctrl && k == LogicalKeyboardKey.digit1) {
      _select(0);
    } else if (ctrl && k == LogicalKeyboardKey.digit2) {
      _select(1);
    } else if (ctrl && k == LogicalKeyboardKey.digit3) {
      _select(2);
    } else if (ctrl && k == LogicalKeyboardKey.keyQ) {
      GillWindow.call('close');
    } else if (!ctrl && k == LogicalKeyboardKey.slash && !_typing) {
      _focusSearch();
    } else if (k == LogicalKeyboardKey.escape && _typing) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      return false;
    }
    return true;
  }

  void _select(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    if (_typing) FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tab = i);
  }

  void _focusSearch() {
    _select(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => SearchScreen.focusSearch?.call());
  }

  @override
  Widget build(BuildContext context) {
    final sys = GillSystem.instance;
    final accent = sys.accent;
    return Listener(
          onPointerDown: (e) {
            if (e.kind == PointerDeviceKind.touch && !_touchMode) {
              setState(() => _lastTouch = DateTime.now());
            } else if (e.kind == PointerDeviceKind.touch) {
              _lastTouch = DateTime.now();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: LayoutBuilder(builder: (context, box) {
              final compact = box.maxWidth < 980; // handhelds: icon-only sidebar
              return Stack(children: [
                Positioned.fill(child: _Backdrop(accent: accent, amoled: sys.amoled)),
                Row(children: [
                  _Sidebar(
                    compact: compact,
                    tab: _tab,
                    accent: accent,
                    amoled: sys.amoled,
                    onSelect: _select,
                  ),
                  Expanded(
                    child: Column(children: [
                      _TitleBar(big: _touchMode, title: _tabs[_tab].label),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 0, compact ? 12 : 20, compact ? 12 : 20),
                          child: _Glass(
                            amoled: sys.amoled,
                            radius: 22,
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1080),
                                child: MediaQuery.removePadding(
                                  context: context,
                                  removeTop: true,
                                  child: IndexedStack(index: _tab, children: const [
                                    SearchScreen(),
                                    FavouritesScreen(),
                                    SettingsScreen(),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ]);
            }),
          ),
    );
  }
}

/// Deep night-blue backdrop with soft glows of the accent colour: what the glass sits on.
class _Backdrop extends StatelessWidget {
  final Color accent;
  final bool amoled;
  const _Backdrop({required this.accent, required this.amoled});

  @override
  Widget build(BuildContext context) {
    if (amoled) return const ColoredBox(color: Colors.black);
    // The window is see-through: the desktop shows through it, frosted by Gill(OS). These tints
    // keep it dark enough to read, with a soft glow of the accent colour in one corner.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x9910131F), Color(0xB307080D)],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1.1, -1.2),
            radius: 1.6,
            colors: [
              accent.withValues(alpha: 0.26),
              accent.withValues(alpha: 0.12),
              accent.withValues(alpha: 0.04),
              accent.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.3, 0.6, 1.0],
          ),
        ),
      ),
    );
  }
}

/// A Liquid Glass panel: translucent, rounded, with a light rim along the top edge.
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool amoled;
  const _Glass({required this.child, this.radius = 22, this.amoled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: amoled ? Colors.black : const Color(0x8C14141A),
        border: Border.all(color: Colors.white.withValues(alpha: amoled ? 0.10 : 0.08), width: 1),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (!amoled) // the glass catches the light at the top
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: 0.075), Colors.white.withValues(alpha: 0.0)],
                    stops: const [0, 0.35],
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(child: Material(type: MaterialType.transparency, child: child)),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final bool compact;
  final int tab;
  final Color accent;
  final bool amoled;
  final ValueChanged<int> onSelect;
  const _Sidebar({
    required this.compact,
    required this.tab,
    required this.accent,
    required this.amoled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 84 : 236,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 12, compact ? 4 : 0, compact ? 12 : 20),
        child: _Glass(
          amoled: amoled,
          radius: 22,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // the top of the sidebar moves the window too
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => GillWindow.call('startDrag'),
              onDoubleTap: () => GillWindow.call('zoom'),
              child: Padding(
                padding: EdgeInsets.fromLTRB(compact ? 0 : 16, 18, compact ? 0 : 12, 18),
                child: Row(
                  mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.asset('assets/icon.png', width: 34, height: 34),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Torrent Search',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            for (final (i, t) in _tabs.indexed)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 10, vertical: 3),
                child: _NavItem(
                  tab: t,
                  selected: i == tab,
                  compact: compact,
                  accent: accent,
                  shortcut: 'Ctrl+${i + 1}',
                  onTap: () => onSelect(i),
                ),
              ),
            const Spacer(),
            if (!compact)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Text('No ads. Results come from public indexes; you are responsible for what you '
                    'download.',
                    style: TextStyle(fontSize: 11, color: Ios.tertiaryLabel, height: 1.35)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final _Tab tab;
  final bool selected, compact;
  final Color accent;
  final String shortcut;
  final VoidCallback onTap;
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.compact,
    required this.accent,
    required this.shortcut,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final fg = sel ? onAccent(widget.accent) : (_hover ? Colors.white : const Color(0xFFD1D1D6));
    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: widget.compact ? 52 : 46,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: sel
                ? widget.accent.withValues(alpha: 0.92)
                : (_hover ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
            boxShadow: sel
                ? [BoxShadow(color: widget.accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))]
                : const [],
          ),
          child: Row(
            mainAxisAlignment: widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(widget.tab.icon, size: widget.compact ? 24 : 20, color: fg),
              if (!widget.compact) ...[
                const SizedBox(width: 12),
                Text(widget.tab.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
              ],
            ],
          ),
        ),
      ),
    );
    return Tooltip(
      message: widget.compact ? '${widget.tab.label}  (${widget.shortcut})' : widget.shortcut,
      waitDuration: const Duration(milliseconds: 700),
      child: item,
    );
  }
}

/// Window title bar: drag to move, double-click to zoom, Gill(OS) buttons on the right.
class _TitleBar extends StatelessWidget {
  final bool big;
  final String title;
  const _TitleBar({required this.big, required this.title});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => GillWindow.call('startDrag'),
      onDoubleTap: () => GillWindow.call('zoom'),
      child: SizedBox(
        height: big ? 60 : 48,
        child: Row(children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: TrafficLights(big: big),
          ),
        ]),
      ),
    );
  }
}

/// macOS-style window buttons in Gill(OS) order (green, yellow, red: close at the edge). Like
/// macOS they show their symbols while the pointer is over them; for fingers they are bigger and
/// sit in a glass capsule with the symbols always on.
class TrafficLights extends StatefulWidget {
  final bool big;
  const TrafficLights({super.key, this.big = false});

  @override
  State<TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<TrafficLights> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.big ? 26.0 : 14.0;
    final gap = widget.big ? 14.0 : 8.0;
    final symbols = _hover || widget.big;
    Widget button(Color c, IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 900),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              child: symbols ? Icon(icon, size: d * 0.7, color: const Color(0x99400000)) : null,
            ),
          ),
        );
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      button(const Color(0xFF28C840), CupertinoIcons.arrow_up_left_arrow_down_right, 'Enter Full Screen', () {
        final alt = HardwareKeyboard.instance.isAltPressed;
        GillWindow.call(alt ? 'zoom' : 'fullscreen');
      }),
      SizedBox(width: gap),
      button(const Color(0xFFFEBC2E), CupertinoIcons.minus, 'Minimise', () => GillWindow.call('minimize')),
      SizedBox(width: gap),
      button(const Color(0xFFFF5F57), CupertinoIcons.xmark, 'Close', () => GillWindow.call('close')),
    ]);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.big
          ? Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(40),
              ),
              child: row,
            )
          : row,
    );
  }
}
