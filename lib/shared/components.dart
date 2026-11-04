import 'package:flutter/material.dart';
import '../app/theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.large = false});
  final bool large;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: large ? 52 : 36,
        height: large ? 52 : 36,
        decoration: BoxDecoration(
          color: Palette.ink,
          borderRadius: BorderRadius.circular(large ? 17 : 12),
        ),
        child: Icon(
          Icons.local_parking_rounded,
          color: Palette.lime,
          size: large ? 34 : 24,
        ),
      ),
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
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
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

/// Circular icon with a short label, used for secondary quick actions.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: enabled ? Colors.white : Colors.white54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 25,
                  color: enabled ? Palette.ink : Palette.muted,
                ),
              ),
              const SizedBox(height: 7),
              ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Palette.ink : Palette.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round close control used in sheet headers.
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
    this.pinFooter = true,
    this.closeTooltip = '닫기',
    this.onClose,
    this.maxWidth = 540,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  /// Confirmation controls kept below the scrolling content when space allows.
  final Widget? footer;

  /// Long confirmations can opt into the content's scroll area.
  final bool pinFooter;
  final String closeTooltip;
  final VoidCallback? onClose;
  final double maxWidth;
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
                  pinFooter &&
                  constraints.maxHeight >= 650 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 20.8;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, sheet ? 18 : 24, 16, 0),
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
                        24 + (sheet ? padding.left : 0),
                        subtitle == null ? 18 : 6,
                        24 + (sheet ? padding.right : 0),
                        pinnedFooter ? 18 : 24 + (sheet ? padding.bottom : 0),
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
                                fontSize: 13.5,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 18),
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
                        24 + (sheet ? padding.left : 0),
                        16,
                        24 + (sheet ? padding.right : 0),
                        20 + (sheet ? padding.bottom : 0),
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
