import 'package:flutter/material.dart';

import '../accelerator.dart';
import '../l10n.dart';
import '../settings.dart';
import '../theme.dart';
import 'components.dart';

/// The two acceleration panes.
enum AccelTab { relay, concurrency }

extension _AccelTabInfo on AccelTab {
  String get title =>
      this == AccelTab.relay ? L.str('relayTab') : L.str('concTab');
  IconData get icon =>
      this == AccelTab.relay ? Icons.lan_outlined : Icons.bolt;
}

/// Open the standalone "加速" page (not an overlay).
Future<void> showAcceleration(BuildContext context) {
  return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccelerationView()));
}

/// Standalone "加速" page. Portrait keeps the tab directory in a bottom bar;
/// landscape mirrors the main three-column layout with the directory on the
/// left and a merged (former middle + right) content pane.
class AccelerationView extends StatefulWidget {
  const AccelerationView({super.key});
  @override
  State<AccelerationView> createState() => _AccelerationViewState();
}

class _AccelerationViewState extends State<AccelerationView> {
  AccelTab _tab = AccelTab.relay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= c.maxHeight;
          return wide ? _landscape(c.maxWidth) : _portrait();
        }),
      ),
    );
  }

  // ============================ Portrait ============================

  Widget _portrait() {
    return Column(
      children: [
        _header(L.str('accelerate')),
        Expanded(child: _content()),
        Container(height: 1, color: T.border),
        // Only two entries — always fits, so no scrolling strip.
        Container(
          color: T.column,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              for (final t in AccelTab.values) ...[
                Expanded(child: _tabButton(t, centered: true)),
                if (t != AccelTab.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ============================ Landscape ============================

  Widget _landscape(double width) {
    return Row(
      children: [
        Container(
          width: width * 0.24,
          color: T.column,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Text(L.str('accelerate'),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: T.text)),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(6),
                  children: [
                    for (final t in AccelTab.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _tabButton(t),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _header(_tab.title),
              Expanded(child: _content()),
            ],
          ),
        ),
      ],
    );
  }

  // ============================ Shared ============================

  Widget _header(String title) {
    return Container(
      height: 44,
      color: T.column,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: T.text)),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 16, color: T.text2),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      child: Align(
        alignment: Alignment.topLeft,
        child: switch (_tab) {
          AccelTab.relay => const _RelayTabView(),
          AccelTab.concurrency => const _ConcurrencyTabView(),
        },
      ),
    );
  }

  /// Directory button styled like the tracked-repo rows.
  Widget _tabButton(AccelTab t, {bool centered = false}) {
    final selected = _tab == t;
    return InkWell(
      onTap: () => setState(() => _tab = t),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? T.rowSelected : T.rowNormal,
          borderRadius: BorderRadius.circular(9),
          border: selected
              ? Border.all(color: Colors.transparent)
              : Border.all(color: T.border),
        ),
        child: Row(
          children: [
            if (centered) const Spacer(),
            Icon(t.icon, size: 14, color: selected ? T.blue : T.text2),
            const SizedBox(width: 8),
            Flexible(
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: T.text)),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ============================ Shared helpers ============================

Widget _accelCard(List<Widget> children, {EdgeInsets? padding}) {
  return GhCard(
    padding: padding ?? const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

Widget _accelSectionTitle(String text) => Text(
      text.toUpperCase(),
      style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.bold, color: T.text2),
    );

Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged) {
  return Row(
    children: [
      Expanded(
        child: Text(title, style: TextStyle(fontSize: 14, color: T.text)),
      ),
      Switch(value: value, activeThumbColor: T.blue, onChanged: onChanged),
    ],
  );
}

// ============================ Relay pane ============================

class _RelayTabView extends StatefulWidget {
  const _RelayTabView();
  @override
  State<_RelayTabView> createState() => _RelayTabViewState();
}

class _RelayTabViewState extends State<_RelayTabView> {
  final Map<String, int> _latency = {}; // host -> ms, -1 = failed
  bool _testing = false;

  Color _colorFor(LatencyGrade g) {
    switch (g) {
      case LatencyGrade.fast:
        return T.green;
      case LatencyGrade.medium:
        return T.brown;
      case LatencyGrade.slow:
      case LatencyGrade.failed:
        return T.red;
    }
  }

  Future<void> _testAll() async {
    setState(() => _testing = true);
    await Future.wait(Accelerator.relayNodes.map((n) async {
      final ms = await Accelerator.measureLatency(n.host);
      if (mounted) setState(() => _latency[n.host] = ms ?? -1);
    }));
    if (mounted) setState(() => _testing = false);
  }

  Widget _nodeRow(RelayNode node) {
    final settings = SettingsStore.i;
    final chosen = settings.relayNode == node.host;
    return InkWell(
      onTap: () => settings.relayNode = node.host,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              chosen
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: chosen ? T.blue : T.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(node.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: T.text)),
            ),
            const SizedBox(width: 8),
            _latencyBadge(node.host),
          ],
        ),
      ),
    );
  }

  Widget _latencyBadge(String host) {
    final ms = _latency[host];
    if (ms == null) {
      return Text('-', style: TextStyle(fontSize: 12, color: T.textMuted));
    }
    final grade = Accelerator.grade(ms < 0 ? null : ms);
    return PillBadge(
      text: ms < 0 ? grade.label : '${ms}ms · ${grade.label}',
      color: _colorFor(grade),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsStore.i,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _accelCard([
            _switchRow(L.str('masterSwitch'), SettingsStore.i.relayEnabled,
                (v) => SettingsStore.i.relayEnabled = v),
          ]),
          const SizedBox(height: 14),
          _accelSectionTitle(L.str('relayNodes')),
          const SizedBox(height: 6),
          _accelCard(
            [
              for (var i = 0; i < Accelerator.relayNodes.length; i++) ...[
                if (i > 0) Divider(height: 1, color: T.border),
                _nodeRow(Accelerator.relayNodes[i]),
              ],
            ],
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _testing ? null : _testAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_testing)
                  SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: T.blue))
                else
                  Icon(Icons.speed, size: 14, color: T.blue),
                const SizedBox(width: 6),
                Text(L.str('testLatency'),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: T.blue)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _accelCard([
            _switchRow(
                L.str('includeArtifacts'),
                SettingsStore.i.relayArtifacts,
                (v) => SettingsStore.i.relayArtifacts = v),
            const SizedBox(height: 6),
            Text(L.str('artifactRiskWarn'),
                style: TextStyle(fontSize: 11, color: T.brown)),
          ]),
          const SizedBox(height: 14),
          Text(L.str('relayHint'),
              style: TextStyle(fontSize: 12, color: T.textMuted)),
        ],
      ),
    );
  }
}

// ============================ Concurrency pane ============================

class _ConcurrencyTabView extends StatelessWidget {
  const _ConcurrencyTabView();

  static const _levels = [2, 4, 8];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsStore.i,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _accelCard([
            _switchRow(L.str('masterSwitch'), SettingsStore.i.concEnabled,
                (v) => SettingsStore.i.concEnabled = v),
          ]),
          const SizedBox(height: 14),
          _accelCard([
            _accelSectionTitle(L.str('concLevel')),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final lvl in _levels)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _levelButton(lvl),
                    ),
                  ),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          _accelCard([
            _switchRow(L.str('includeArtifacts'), SettingsStore.i.concArtifacts,
                (v) => SettingsStore.i.concArtifacts = v),
            const SizedBox(height: 6),
            Text(L.str('artifactRiskWarn'),
                style: TextStyle(fontSize: 11, color: T.brown)),
          ]),
          const SizedBox(height: 14),
          Text(L.str('concHint'),
              style: TextStyle(fontSize: 12, color: T.textMuted)),
        ],
      ),
    );
  }

  Widget _levelButton(int lvl) {
    final selected = SettingsStore.i.concLevel == lvl;
    return InkWell(
      onTap: () => SettingsStore.i.concLevel = lvl,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? T.blue : T.rowNormal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? T.blue : T.border),
        ),
        child: Center(
          child: Text('$lvl',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : T.text)),
        ),
      ),
    );
  }
}