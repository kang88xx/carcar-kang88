import 'package:flutter/material.dart';
import '../app/theme.dart';

/// App name beside the launcher pin. Pass the supported parked [floor] so the
/// header mark follows the launcher icon (null shows the default car pin).
class Brand extends StatelessWidget {
  const Brand({super.key, this.large = false, this.floor});
  final bool large;
  final String? floor;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PinMark(size: large ? 52 : 36, floor: floor),
      const SizedBox(width: 10),
      Text(
        '차자리',
        style: TextStyle(
          fontSize: large ? 28 : 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.1,
          color: Palette.ink,
        ),
      ),
    ],
  );
}

/// The 차자리 pin mark used by the launcher icon, drawn in the app's own
/// geometry (1024-unit design space). The pin holds the car by default and the
/// parked floor label (F1–F5, B1–B6) otherwise, like the alternate launcher
/// icons. The header shows the saved floor at once; the launcher icon follows
/// under its own conditions (supported platform, active app, native success).
class PinMark extends StatelessWidget {
  const PinMark({super.key, this.size = 36, this.floor});
  final double size;
  final String? floor;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: floor == null ? '차자리 마크' : '차자리 마크, 주차 층 $floor',
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PinPainter(floor)),
      ),
    ),
  );
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.floor);
  final String? floor;
  static const _accentDeep = Palette.accentDeep;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 1024);
    final blue = Paint()..color = Palette.accent;
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 1024, 1024),
        const Radius.circular(300),
      ),
      blue,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(512, 846), width: 260, height: 52),
      Paint()..color = _accentDeep,
    );
    final pin = Path()
      ..moveTo(512, 830)
      ..cubicTo(420, 700, 276, 590, 276, 430)
      ..arcToPoint(const Offset(748, 430), radius: const Radius.circular(236))
      ..cubicTo(748, 590, 604, 700, 512, 830)
      ..close();
    canvas.drawPath(pin, white);
    final label = floor;
    if (label == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(432, 290, 160, 280),
          const Radius.circular(60),
        ),
        blue,
      );
      canvas.drawCircle(const Offset(424, 382), 16, blue);
      canvas.drawCircle(const Offset(600, 382), 16, blue);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(454, 344, 116, 58),
          const Radius.circular(18),
        ),
        white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(454, 470, 116, 44),
          const Radius.circular(14),
        ),
        white,
      );
      return;
    }
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 236,
          fontWeight: FontWeight.w700,
          color: Palette.accent,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    text.paint(canvas, Offset(512 - text.width / 2, 430 - text.height / 2));
    text.dispose();
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.floor != floor;
}

/// Borderless white card. Pass [color] for a tinted card.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color = Colors.white,
    this.radius = 24,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    child: Padding(padding: padding, child: child),
  );
}

/// Section heading placed on the canvas above a card group.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// Small muted label above a grouped settings card.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: Palette.muted),
    ),
  );
}

/// Hairline between rows inside a card group.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 18),
    child: Divider(),
  );
}

const _rowPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 4);
const _rowTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
const _rowSubtitle = TextStyle(
  fontSize: 12.5,
  color: Palette.muted,
  height: 1.6,
);

/// Tappable row inside a white card group with icon, chevron and subtitle.
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final color = destructive ? Palette.roseInk : Palette.ink;
    return ListTile(
      onTap: onTap,
      enabled: onTap != null || trailing != null,
      contentPadding: _rowPadding,
      minVerticalPadding: 12,
      leading: icon == null ? null : Icon(icon, color: color, size: 23),
      title: Text(title, style: _rowTitle.copyWith(color: color)),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(subtitle!, style: _rowSubtitle),
            ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Palette.muted,
                )),
    );
  }
}

/// Switch row styled like [ActionRow] for card groups.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: _rowPadding,
    secondary: icon == null ? null : Icon(icon, size: 23),
    title: Text(title, style: _rowTitle),
    subtitle: subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(subtitle!, style: _rowSubtitle),
          ),
    value: value,
    onChanged: onChanged,
  );
}

class RoundCloseButton extends StatelessWidget {
  const RoundCloseButton({super.key, required this.tooltip, this.onPressed});
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    style: IconButton.styleFrom(
      backgroundColor: Palette.soft,
      disabledBackgroundColor: Palette.canvas,
      fixedSize: const Size(48, 48),
    ),
    icon: const Icon(Icons.close_rounded, size: 22),
  );
}

/// Opens [SheetDialog] content. Safe-area insets are handled by the sheet so
/// it can reach the bottom edge on phones.
Future<T?> showSheetDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  useSafeArea: false,
  builder: builder,
);

/// A [Dialog] presented as a bottom sheet on phones and a centered card on
/// wide screens. Keeps [Dialog] semantics for tests and QA scripts.
class SheetDialog extends StatelessWidget {
  const SheetDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.closeTooltip = '닫기',
    this.onClose,
    this.maxWidth = 540,
    this.horizontalPadding = 24,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  /// Confirmation controls kept below the scrolling content when space allows.
  final Widget? footer;

  final String closeTooltip;
  final VoidCallback? onClose;
  final double maxWidth;
  final double horizontalPadding;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final sheet = size.width < wideLayoutBreakpoint;
    final radius = sheet
        ? const BorderRadius.vertical(top: Radius.circular(28))
        : BorderRadius.circular(28);
    return Dialog(
      alignment: sheet ? Alignment.bottomCenter : Alignment.center,
      insetPadding: sheet
          ? EdgeInsets.only(top: padding.top + 24)
          : EdgeInsets.fromLTRB(
              24 + padding.left,
              32 + padding.top,
              24 + padding.right,
              32 + padding.bottom,
            ),
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: title,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: sheet ? double.infinity : maxWidth,
            maxHeight: size.height * (sheet ? .92 : .88),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Dialog has already removed keyboard insets from these bounds.
              // Large text or a short viewport needs one scrollable region.
              final pinnedFooter =
                  footer != null &&
                  constraints.maxHeight >= 650 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 20.8;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      sheet ? 16 : 24,
                      horizontalPadding,
                      0,
                    ),
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: headlineMaxTextScale,
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontSize: sheet ? 20 : 22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          RoundCloseButton(
                            tooltip: closeTooltip,
                            onPressed: onClose,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding + (sheet ? padding.left : 0),
                        subtitle == null ? 16 : 6,
                        horizontalPadding + (sheet ? padding.right : 0),
                        pinnedFooter ? 16 : 16 + (sheet ? padding.bottom : 0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (subtitle != null) ...[
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: Palette.muted,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          child,
                          if (footer != null && !pinnedFooter) ...[
                            const SizedBox(height: 18),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (pinnedFooter) ...[
                    const Divider(),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding + (sheet ? padding.left : 0),
                        12,
                        horizontalPadding + (sheet ? padding.right : 0),
                        12 + (sheet ? padding.bottom : 0),
                      ),
                      child: footer,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class StatusNotice extends StatelessWidget {
  const StatusNotice(this.text, {super.key, this.error = false, this.onRetry});
  final String text;
  final bool error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
    decoration: BoxDecoration(
      color: error ? Palette.rose : Palette.info,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(
          error ? Icons.wifi_off_rounded : Icons.info_outline_rounded,
          size: 20,
          color: error ? Palette.roseInk : Palette.ink,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: error ? Palette.roseInk : Palette.ink,
            ),
          ),
        ),
        if (onRetry != null)
          IconButton(
            onPressed: onRetry,
            tooltip: '다시 시도',
            icon: const Icon(Icons.refresh_rounded),
          )
        else
          const SizedBox(width: 8),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Palette.tint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 34, color: Palette.ink),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.muted, height: 1.6),
        ),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String action = '확인',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? Semantics(
              label: '$label 처리 중',
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Palette.muted,
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    ),
  );
}

/// Time-of-day greeting used as the home headline. A name is prepended
/// with the polite suffix.
String greetingFor(DateTime now, {String? name}) {
  final hour = now.hour;
  final greeting = hour < 5
      ? '늦은 밤이에요'
      : hour < 11
      ? '좋은 아침이에요'
      : hour < 14
      ? '즐거운 점심시간이에요'
      : hour < 18
      ? '편안한 오후 보내세요'
      : '좋은 저녁이에요';
  return name == null ? greeting : '$name님, $greeting';
}

/// Human floor label for a configured floor code, or null when the code is
/// not a plain B/F number.
String? floorDescription(String floor) {
  final match = RegExp(r'^([BF])(\d{1,3})$').firstMatch(floor.toUpperCase());
  if (match == null) return null;
  return '${match.group(1) == 'B' ? '지하' : '지상'} ${int.parse(match.group(2)!)}층';
}
