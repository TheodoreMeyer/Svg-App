import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const pixelHeading = TextStyle(
  fontFamily: 'PressStart2P',
  fontSize: 12,
  height: 1.65,
);

ThemeData minecraftTheme() {
  const scheme = ColorScheme.light(
    primary: Color(0xFF326F20),
    onPrimary: Colors.white,
    secondary: Color(0xFF4C4879),
    onSecondary: Colors.white,
    surface: Color(0xFFC6C6C6),
    onSurface: Color(0xFF232323),
    error: Color(0xFF9B211C),
  );
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
    textStyle: const WidgetStatePropertyAll(pixelHeading),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF221B15),
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      backgroundColor: Color(0xFFC6C6C6),
      foregroundColor: Color(0xFF232323),
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF252525),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      labelStyle: TextStyle(color: Color(0xFFE4E4E4)),
      hintStyle: TextStyle(color: Color(0xFFBDBDBD)),
      suffixIconColor: Color(0xFFE4E4E4),
      errorMaxLines: 4,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.zero),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Color(0xFFF3F3F3), width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Color(0xFF80BA67), width: 2),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Color(0xFFB2DB9F),
      selectionColor: Color(0xFF59744C),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle.copyWith(
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(),
      backgroundColor: Color(0xFFC6C6C6),
    ),
  );
}

class DirtBackground extends StatelessWidget {
  const DirtBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/textures/dirt.png'),
          repeat: ImageRepeat.repeat,
          scale: 0.25,
          filterQuality: FilterQuality.none,
          colorFilter: ColorFilter.mode(Color(0xAA000000), BlendMode.srcOver),
        ),
      ),
      child: child,
    ),
  );
}

class BeveledPanel extends StatelessWidget {
  const BeveledPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0xFFC6C6C6),
      border: Border(
        top: BorderSide(color: Color(0xFFF4F4F4), width: 4),
        left: BorderSide(color: Color(0xFFF4F4F4), width: 4),
        right: BorderSide(color: Color(0xFF535353), width: 4),
        bottom: BorderSide(color: Color(0xFF535353), width: 4),
      ),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class StoneButton extends StatelessWidget {
  const StoneButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      side: const WidgetStatePropertyAll(
        BorderSide(color: Color(0xFF222222), width: 2),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? const Color(0xFFBDBDBD)
            : Colors.white,
      ),
      backgroundColor: WidgetStatePropertyAll(
        primary ? const Color(0xFF326F20) : const Color(0xFF666666),
      ),
    ),
    onPressed: onPressed,
    child: LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
        child: Ink(
          decoration: BoxDecoration(
            image: const DecorationImage(
              image: AssetImage('assets/textures/stone.png'),
              repeat: ImageRepeat.repeat,
              filterQuality: FilterQuality.none,
              opacity: 0.15,
            ),
            border: Border(
              top: BorderSide(
                color: primary
                    ? const Color(0xFF81AA70)
                    : const Color(0xFFAAAAAA),
                width: 2,
              ),
              left: BorderSide(
                color: primary
                    ? const Color(0xFF81AA70)
                    : const Color(0xFFAAAAAA),
                width: 2,
              ),
              right: const BorderSide(color: Color(0xFF333333), width: 2),
              bottom: const BorderSide(color: Color(0xFF333333), width: 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      shadows: [
                        Shadow(offset: Offset(1, 1), color: Colors.black),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HoldToTalk extends StatefulWidget {
  const HoldToTalk({
    super.key,
    required this.available,
    required this.enabled,
    required this.label,
    required this.talkingLabel,
    required this.hint,
    required this.onTalkingChanged,
  });
  final ValueNotifier<bool> available;
  final bool enabled;
  final String label;
  final String talkingLabel;
  final String hint;
  final ValueChanged<bool> onTalkingChanged;

  @override
  State<HoldToTalk> createState() => _HoldToTalkState();
}

class _HoldToTalkState extends State<HoldToTalk> with WidgetsBindingObserver {
  bool _talking = false;

  @override
  void initState() {
    super.initState();
    widget.available.addListener(_availabilityChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(HoldToTalk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _talking = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _setTalking(false);
  }

  void _availabilityChanged() {
    if (!widget.available.value) _setTalking(false);
    if (mounted) setState(() {});
  }

  void _setTalking(bool talking) {
    talking = talking && widget.enabled && widget.available.value;
    if (_talking == talking) return;
    setState(() => _talking = talking);
    widget.onTalkingChanged(talking);
  }

  @override
  void dispose() {
    widget.available.removeListener(_availabilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.available.value;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: _talking,
      label: _talking ? widget.talkingLabel : widget.label,
      hint: widget.hint,
      onTap: enabled ? () => _setTalking(!_talking) : null,
      child: FocusableActionDetector(
        enabled: enabled,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _setTalking(!_talking);
              return null;
            },
          ),
        },
        child: GestureDetector(
          excludeFromSemantics: true,
          onTapDown: enabled ? (_) => _setTalking(true) : null,
          onTapUp: (_) => _setTalking(false),
          onTapCancel: () => _setTalking(false),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: !enabled
                  ? const Color(0xFF666666)
                  : _talking
                  ? const Color(0xFF326F20)
                  : const Color(0xFF4C4879),
              border: Border.all(color: const Color(0xFF232323), width: 3),
            ),
            child: ExcludeSemantics(
              child: Text(
                _talking ? widget.talkingLabel : widget.label,
                textAlign: TextAlign.center,
                style: pixelHeading.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
