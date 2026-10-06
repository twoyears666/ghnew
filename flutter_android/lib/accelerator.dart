import 'package:http/http.dart' as http;

import 'l10n.dart';

/// A GitHub download mirror ("中转") node. Mirrors are the public ones listed on
/// fastlist.pages.dev; ghnew only reuses the idea, not FastList's UI.
class RelayNode {
  final String host;
  const RelayNode(this.host);
  String get id => host;
}

/// Latency bucket used by the "测试节点延迟" readout.
enum LatencyGrade {
  fast,
  medium,
  slow,
  failed;

  String get label {
    switch (this) {
      case LatencyGrade.fast:
        return L.str('latencyFast');
      case LatencyGrade.medium:
        return L.str('latencyMedium');
      case LatencyGrade.slow:
        return L.str('latencySlow');
      case LatencyGrade.failed:
        return L.str('latencyFail');
    }
  }
}

/// Download acceleration helpers: relay-node catalog, URL rewriting and a
/// best-effort latency probe (port of Accelerator.swift).
class Accelerator {
  Accelerator._();

  /// Public mirrors, in the order FastList lists them.
  static const relayNodes = <RelayNode>[
    RelayNode('gh-proxy.com'),
    RelayNode('ghproxy.net'),
    RelayNode('edgeone.gh-proxy.com'),
    RelayNode('cdn.gh-proxy.com'),
    RelayNode('hk.gh-proxy.com'),
    RelayNode('gh.llkk.cc'),
    RelayNode('ghproxy.fangkuai.fun'),
    RelayNode('ghproxy.imciel.com'),
    RelayNode('ui.ghproxy.cc'),
    RelayNode('gitproxy.click'),
    RelayNode('ghproxy.link'),
    RelayNode('iacc.eu.org'),
    RelayNode('gh.jasonzeng.dev'),
    RelayNode('gh-proxy.org'),
    RelayNode('hk.gh-proxy.org'),
    RelayNode('cdn.gh-proxy.org'),
    RelayNode('edgeone.gh-proxy.org'),
  ];

  static const defaultNodeHost = 'gh-proxy.com';

  /// Rewrite an original URL so it is fetched through `host`
  /// (`https://{host}/{original}`).
  static String? rewrite(String original, String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return null;
    return 'https://$trimmed/$original';
  }

  /// Fetch a small known file through the node and time it. Returns milliseconds
  /// or null when the node fails. Best-effort: a failure is not fatal.
  static Future<int?> measureLatency(String host) async {
    const target =
        'https://github.com/github/gitignore/raw/main/Swift.gitignore';
    final uri = Uri.tryParse('https://$host/$target');
    if (uri == null) return null;
    final sw = Stopwatch()..start();
    try {
      final resp = await http
          .get(uri, headers: {'User-Agent': 'ghnew/1.0'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// Bucket a measured latency.
  static LatencyGrade grade(int? milliseconds) {
    if (milliseconds == null) return LatencyGrade.failed;
    if (milliseconds < 100) return LatencyGrade.fast;
    if (milliseconds <= 300) return LatencyGrade.medium;
    return LatencyGrade.slow;
  }
}