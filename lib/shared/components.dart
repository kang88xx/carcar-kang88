import 'package:flutter/material.dart';
import '../app/theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.large = false, this.showName = true});
  final bool large, showName;
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
      if (showName) ...[
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
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Palette.muted,
      ),
    ),
  );
}

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
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      minVerticalPadding: 12,
      leading: icon == null ? null : Icon(icon, color: color, size: 23),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Palette.muted,
                  height: 1.6,
                ),
              ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
class CloseButton2 extends StatelessWidget {
  const CloseButton2({super.key, required this.tooltip, this.onPressed});
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    style: IconButton.styleFrom(
      backgroundColor: Palette.soft,
      disabledBackgroundColor: Palette.canvas,
      fixedSize: const Size(44, 44),
    ),
    icon: const Icon(Icons.close_rounded, size: 22),
  );
}

/// A [Dialog] presented as a bottom sheet on phones and a centered card on
/// wide screens. Keeps [Dialog] semantics for tests and QA scripts.
class SheetDialog extends StatelessWidget {
  const SheetDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.closeTooltip = '닫기',
    this.onClose,
    this.maxWidth = 540,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final String closeTooltip;
  final VoidCallback? onClose;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sheet = size.width < 640;
    final radius = sheet
        ? const BorderRadius.vertical(top: Radius.circular(28))
        : BorderRadius.circular(28);
    return Dialog(
      alignment: sheet ? Alignment.bottomCenter : Alignment.center,
      insetPadding: sheet
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: sheet ? double.infinity : maxWidth,
          maxHeight: size.height * (sheet ? .92 : .88),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sheet)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Palette.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, sheet ? 14 : 24, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(fontSize: 22),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              color: Palette.muted,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  CloseButton2(tooltip: closeTooltip, onPressed: onClose),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  sheet ? 24 + MediaQuery.paddingOf(context).bottom : 24,
                ),
                child: child,
              ),
            ),
          ],
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
      color: error ? Palette.rose : const Color(0xFFE6EBF6),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Palette.muted,
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

/// Time-of-day greeting used as the home headline.
String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 5) return '늦은 밤이에요';
  if (hour < 11) return '좋은 아침이에요';
  if (hour < 14) return '좋은 점심이에요';
  if (hour < 18) return '좋은 오후예요';
  return '좋은 저녁이에요';
}
