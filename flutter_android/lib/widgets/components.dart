import 'package:flutter/material.dart';

import '../download_manager.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';

/// White rounded card with a light-blue-gray border and subtle shadow (ghCard).
class GhCard extends StatelessWidget {
  const GhCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: T.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: T.border, width: 1),
        boxShadow: [BoxShadow(color: T.shadow, blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: child,
    );
  }
}

/// Hollow capsule pill (release badge).
class PillBadge extends StatelessWidget {
  const PillBadge({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Light-blue rounded-rect branch badge.
class BranchBadge extends StatelessWidget {
  const BranchBadge({super.key, this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final n = name;
    if (n == null || n.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: T.branchBg, borderRadius: BorderRadius.circular(5)),
      child: Text(n,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: T.branchText)),
    );
  }
}

/// Section header used in the right column.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: T.text2, letterSpacing: 0.5)),
    );
  }
}

/// Action run status icon: green check / red x / muted x / clock / spinner.
class RunStatusView extends StatelessWidget {
  const RunStatusView({super.key, required this.message});
  final GHMessage message;

  @override
  Widget build(BuildContext context) {
    final size = 22.0;
    if (message.runStatus == 'completed') {
      switch (message.runConclusion) {
        case 'success':
          return Icon(Icons.check_circle, size: size, color: T.green);
        case 'failure':
        case 'startup_failure':
          return Icon(Icons.cancel, size: size, color: T.red);
        case 'cancelled':
        case 'timed_out':
        case 'action_required':
        case 'neutral':
        case 'skipped':
          return Icon(Icons.cancel, size: size, color: T.textMuted);
        default:
          return Icon(Icons.circle_outlined, size: size, color: T.textMuted);
      }
    } else if (message.runStatus == 'queued' || message.runStatus == 'pending') {
      return Icon(Icons.access_time, size: size, color: T.text2);
    } else {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: T.blue),
      );
    }
  }
}

/// A progress bar for a workflow run: solid when done, animated while running.
class ActionProgressView extends StatefulWidget {
  const ActionProgressView({super.key, required this.message});
  final GHMessage message;

  @override
  State<ActionProgressView> createState() => _ActionProgressViewState();
}

class _ActionProgressViewState extends State<ActionProgressView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  bool get _isDone => widget.message.runStatus == 'completed';

  Color get _fillColor {
    if (_isDone && widget.message.runConclusion == 'success') return T.green;
    if (_isDone) return T.red;
    return T.blue;
  }

  String get _statusText {
    if (_isDone) {
      final c = widget.message.runConclusion;
      return c == null ? 'Completed' : c[0].toUpperCase() + c.substring(1);
    }
    if (widget.message.runStatus == 'queued' ||
        widget.message.runStatus == 'pending') {
      return 'Queued';
    }
    return 'In progress';
  }

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    if (!_isDone) _ctl.repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_statusText,
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _fillColor)),
            const Spacer(),
            Text(Fmt.duration(widget.message.duration),
                style: TextStyle(fontSize: 12, color: T.text2)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Container(
            height: 8,
            decoration: BoxDecoration(
                color: T.border,
                borderRadius: BorderRadius.circular(999)),
            child: _isDone
                ? FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Container(
                        decoration: BoxDecoration(
                            color: _fillColor,
                            borderRadius: BorderRadius.circular(999))))
                : AnimatedBuilder(
                    animation: _ctl,
                    builder: (context, _) => Align(
                          alignment: Alignment(-1 + 2 * _ctl.value, 0),
                          child: Container(
                            width: w * 0.4,
                            decoration: BoxDecoration(
                                color: _fillColor,
                                borderRadius: BorderRadius.circular(999)),
                          ),
                        ),
                  ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A single downloadable row: name + size + download / progress / done / retry.
class DownloadRow extends StatelessWidget {
  const DownloadRow({
    super.key,
    required this.keyValue,
    required this.name,
    this.size,
    required this.url,
    required this.needsAuth,
    this.onLogin,
  });

  final String keyValue;
  final String name;
  final int? size;
  final String? url;
  final bool needsAuth;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    final loginRequired = onLogin != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(needsAuth ? Icons.archive_outlined : Icons.attach_file,
              size: 14, color: T.text2),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500, color: T.text)),
                if (size != null && size! >= 0)
                  Text(DownloadManager.bytesString(size),
                      style: TextStyle(fontSize: 11, color: T.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: DownloadManager.shared,
            builder: (context, _) {
              final item = DownloadManager.shared.itemFor(keyValue);
              if (item == null) {
                return InkWell(
                  onTap: (url == null) ? null : () => _start(),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_circle_down_outlined, size: 13, color: T.blue),
                        const SizedBox(width: 4),
                        Text(L.str('download'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: T.blue)),
                      ]),
                );
              }
              return DownloadStateView(key: ValueKey(item.id), item: item, onLogin: onLogin);
            },
          ),
        ],
      ),
    );
  }

  void _start() {
    if (url == null) return;
    DownloadManager.shared.download(
        key: keyValue, name: name, size: size, url: url!, needsAuth: needsAuth);
  }
}

class DownloadStateView extends StatelessWidget {
  const DownloadStateView({super.key, required this.item, this.onLogin});
  final DownloadItem item;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: item,
      builder: (context, _) {
        switch (item.state) {
          case DlState.downloading:
            return SizedBox(
              width: 70,
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: item.progress, minHeight: 6, color: T.blue, backgroundColor: T.border),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${(item.progress * 100).round()}%',
                      style: TextStyle(fontSize: 11, color: T.text2)),
                ],
              ),
            );
          case DlState.done:
            return InkWell(
              onTap: () => DownloadManager.shared.reveal(item),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 13, color: T.green),
                    const SizedBox(width: 4),
                    Text(L.str('downloaded'),
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: T.green)),
                  ]),
            );
          case DlState.failed:
            return InkWell(
              onTap: () => DownloadManager.shared.download(
                  key: item.id,
                  name: item.name,
                  size: item.size,
                  url: item.url,
                  needsAuth: item.needsAuth),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 13, color: T.red),
                    const SizedBox(width: 4),
                    Text(L.str('downloadFailed'),
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: T.red)),
                  ]),
            );
          case DlState.authRequired:
            return InkWell(
              onTap: onLogin,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: T.blue),
                    const SizedBox(width: 4),
                    Text(L.str('loginToGetArtifacts'),
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: T.blue)),
                  ]),
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}