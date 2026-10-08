import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'accelerator.dart';
import 'github_api.dart';
import 'l10n.dart';
import 'settings.dart';

/// Root navigator, so a download finishing without a `BuildContext` can still
/// raise the "open folder" prompt.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

enum DlState { idle, downloading, done, failed, authRequired }

class DownloadItem extends ChangeNotifier {
  final String id;
  final String name;
  final int? size;
  final String url;
  final bool needsAuth;

  DlState state = DlState.idle;
  double progress = 0;
  String? error;
  String? filePath;

  DownloadItem({
    required this.id,
    required this.name,
    this.size,
    required this.url,
    this.needsAuth = false,
  });
}

/// Central download manager (port of DownloadManager.swift). Uses http's
/// streaming send to report byte-level progress, and optionally routes through a
/// relay node and/or splits a single file into parallel byte-range chunks.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager shared = DownloadManager._();

  /// Below this size a chunked download is not worth the overhead.
  static const _chunkThreshold = 1048576; // 1 MB

  /// Absolute cap on simultaneous range connections across *every* active
  /// download, so several parallel downloads can't multiply into a flood.
  static const _globalConnectionLimit = 6;
  /// The widest a single download's window is ever allowed to become.
  static const _hardWindowCap = 8;
  /// Connections a download opens with, before ramping toward its target.
  static const _initialWindow = 2;
  /// Most transport/HTTP errors a single chunk may suffer before we give up.
  static const _maxAttempts = 4;
  /// Most rate-limit responses a single chunk may hit before we give up.
  static const _maxRateLimitEvents = 12;
  /// After a rate-limit, ignore window ramping for this long to avoid flapping.
  static const _rampQuiet = Duration(seconds: 20);
  /// Longest single cool-down / Retry-After wait.
  static const _maxCoolDown = Duration(seconds: 60);

  /// Range connections currently in flight across all downloads.
  int _globalActive = 0;

  final Map<String, DownloadItem> _items = {};
  DownloadItem? itemFor(String key) => _items[key];

  void download({
    required String key,
    required String name,
    int? size,
    required String url,
    required bool needsAuth,
  }) {
    final t = GitHubApi.shared.token;
    final loggedIn = t != null && t.isNotEmpty;
    if (needsAuth && !loggedIn) {
      final item = DownloadItem(
          id: key, name: name, size: size, url: url, needsAuth: needsAuth);
      item.state = DlState.authRequired;
      _items[key] = item;
      notifyListeners();
      return;
    }
    final token = loggedIn ? t : null;
    final isArtifact = key.startsWith('act-');
    final s = SettingsStore.i;

    // 中转: route the request through the selected mirror node.
    var effective = url;
    if (s.relayEnabled && (!isArtifact || s.relayArtifacts)) {
      final rewritten = Accelerator.rewrite(url, s.relayNode);
      if (rewritten != null) effective = rewritten;
    }

    // 并发: multi-connection byte-range download.
    if (s.concEnabled && (!isArtifact || s.concArtifacts)) {
      _startChunked(key, name, size, effective, token);
    } else {
      _start(key, name, size, effective, token);
    }
  }

  Map<String, String> _headers(String? token) {
    final h = <String, String>{
      'User-Agent': 'ghnew/1.0',
      'Accept': 'application/vnd.github+json',
    };
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Future<Directory> _downloadDir() async {
    final dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'Downloads'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _start(
      String key, String name, int? size, String url, String? token) async {
    final item = DownloadItem(
        id: key, name: name, size: size, url: url, needsAuth: token != null);
    item.state = DlState.downloading;
    item.progress = 0;
    item.error = null;
    _items[key] = item;
    notifyListeners();

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers.addAll(_headers(token));
      final resp = await client.send(req).timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        await resp.stream.drain<void>();
        item.state = DlState.failed;
        item.error = 'HTTP ${resp.statusCode}';
        notifyListeners();
        return;
      }
      final total = resp.contentLength ?? 0;
      int received = 0;
      final file = await _targetFile(await _downloadDir(), item);
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            item.progress = (received / total).clamp(0.0, 1.0).toDouble();
          }
          notifyListeners();
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        rethrow;
      }
      item.filePath = file.path;
      item.state = DlState.done;
      item.progress = 1;
      notifyListeners();
      unawaited(_finish(item, file));
    } catch (e) {
      item.state = DlState.failed;
      item.error = e.toString();
      notifyListeners();
    } finally {
      client.close();
    }
  }

  /// Probe the effective URL, then start a chunked download — falling back to a
  /// plain single-thread download when the file is small or ranges are
  /// unsupported.
  Future<void> _startChunked(
      String key, String name, int? size, String url, String? token) async {
    final level = _clampLevel(SettingsStore.i.concLevel);
    final total = await _probeTotal(url, token);
    if (total == null || total <= _chunkThreshold) {
      await _start(key, name, size, url, token);
      return;
    }
    final dir = await _downloadDir();
    final target = await _uniqueFile(dir, _desiredFileName(key, name));
    final item = DownloadItem(
        id: key, name: name, size: total, url: url, needsAuth: token != null);
    item.state = DlState.downloading;
    item.progress = 0;
    _items[key] = item;
    notifyListeners();
    await _runChunks(item, url, token, total, level, target);
  }

  static int _clampLevel(int level) => level < 2 ? 2 : (level > 8 ? 8 : level);

  /// Ask the server for the total size via a 1-byte range request. Returns null
  /// unless it answers 206 with a parseable `Content-Range`.
  Future<int?> _probeTotal(String url, String? token) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers.addAll(_headers(token));
      req.headers['Range'] = 'bytes=0-0';
      final resp = await client.send(req).timeout(const Duration(seconds: 20));
      await resp.stream.drain<void>();
      if (resp.statusCode != 206) return null;
      final cr = resp.headers['content-range'];
      if (cr == null) return null;
      final m = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(cr);
      if (m == null) return null;
      return int.tryParse(m.group(1)!);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Download `url` into `target` in parallel byte-range chunks.
  ///
  /// Concurrency is deliberately conservative so a burst of parallel range
  /// requests does not trip GitHub/CDN rate limits: chunks are fed through a
  /// bounded window that starts small, ramps up while the server stays happy and
  /// shrinks (down to a single connection) on 429/403/503. Rate-limited chunks
  /// are re-queued after `Retry-After`, and a shared connection budget keeps N
  /// simultaneous downloads from multiplying into N×level connections.
  Future<void> _runChunks(DownloadItem item, String url, String? token,
      int total, int level, File target) async {
    final safeKey = item.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final partDir = await Directory(
            p.join(Directory.systemTemp.path, 'ghnew_parts_$safeKey'))
        .create(recursive: true);

    // Split [0, total) into `level` contiguous byte ranges.
    final chunkSize = (total / level).ceil();
    final chunks = <_Chunk>[];
    var start = 0;
    while (start < total) {
      final end = (start + chunkSize - 1 < total - 1) ? start + chunkSize - 1 : total - 1;
      chunks.add(_Chunk(start, end));
      start = end + 1;
    }

    final received = List<int>.filled(chunks.length, 0);
    var reported = 0; // monotonic progress high-water mark
    final pending = <int>[for (var i = 0; i < chunks.length; i++) i];
    final running = <int>{};
    final waiting = <_Waiting>[];

    final maxWindow = level < 2 ? 2 : (level > _hardWindowCap ? _hardWindowCap : level);
    var window = maxWindow < _initialWindow ? maxWindow : _initialWindow;
    DateTime? cooldownUntil;
    DateTime? lastRateLimit;
    Object? fatalError;

    Future<void> fetch(int i) async {
      final c = chunks[i];
      received[i] = 0; // a fresh attempt restarts this chunk's counter
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(url));
        req.headers.addAll(_headers(token));
        req.headers['Range'] = 'bytes=${c.start}-${c.end}';
        final resp = await client.send(req).timeout(const Duration(seconds: 30));
        final status = resp.statusCode;

        if (_isRateLimit(status, resp)) {
          await resp.stream.drain<void>();
          c.rateLimitEvents++;
          if (c.rateLimitEvents > _maxRateLimitEvents) {
            fatalError = Exception('HTTP $status (rate limited)');
            return;
          }
          final delay = _retryAfter(resp);
          window = window ~/ 2 < 1 ? 1 : window ~/ 2;
          lastRateLimit = DateTime.now();
          cooldownUntil = DateTime.now().add(delay);
          waiting.add(_Waiting(i, DateTime.now().add(delay)));
          return;
        }
        if (status != 206) {
          await resp.stream.drain<void>();
          throw _HttpException(status);
        }

        final part = File(p.join(partDir.path, 'part_$i'));
        final sink = part.openWrite();
        try {
          await for (final chunk in resp.stream) {
            sink.add(chunk);
            received[i] += chunk.length;
            // A retried chunk restarts from zero, so a raw sum can drop and make
            // the bar jump backwards. Report a monotonic high-water mark instead.
            final sum = received.fold<int>(0, (a, b) => a + b);
            if (sum > reported) reported = sum;
            item.progress = (reported / total).clamp(0.0, 1.0).toDouble();
            notifyListeners();
          }
          await sink.flush();
          await sink.close();
        } catch (_) {
          await sink.close();
          rethrow;
        }

        final expected = c.end - c.start + 1;
        if (await part.length() != expected) {
          throw Exception('Short read');   // truncated / error body
        }
        c.file = part;
        // Widen slowly, and only after the server has been quiet for a while.
        if (lastRateLimit == null ||
            DateTime.now().difference(lastRateLimit!) > _rampQuiet) {
          if (window < maxWindow) window++;
        }
      } catch (e) {
        c.attempts++;
        if (c.attempts > _maxAttempts) {
          fatalError = e;
          return;
        }
        waiting.add(_Waiting(i, DateTime.now().add(_backoff(c.attempts))));
      } finally {
        client.close();
      }
    }

    try {
      while (true) {
        if (fatalError != null) break;
        final now = DateTime.now();

        if (cooldownUntil != null && now.isBefore(cooldownUntil!)) {
          final remaining = cooldownUntil!.difference(now);
          await Future.delayed(
              remaining > const Duration(milliseconds: 200)
                  ? const Duration(milliseconds: 200)
                  : remaining);
          continue;
        }
        cooldownUntil = null;

        // Promote chunks whose back-off / cool-down has elapsed.
        for (final w in waiting.toList()) {
          if (!w.readyAt.isAfter(now)) {
            waiting.remove(w);
            pending.add(w.index);
          }
        }

        if (pending.isEmpty && running.isEmpty && waiting.isEmpty) break;

        if (pending.isEmpty ||
            running.length >= window ||
            _globalActive >= _globalConnectionLimit) {
          await Future.delayed(const Duration(milliseconds: 60));
          continue;
        }

        final idx = pending.removeAt(0);
        running.add(idx);
        _globalActive++;
        unawaited(fetch(idx).whenComplete(() {
          running.remove(idx);
          if (_globalActive > 0) _globalActive--;
        }));
      }

      if (fatalError != null) {
        item.state = DlState.failed;
        item.error = fatalError.toString();
        notifyListeners();
        return;
      }

      final sink = target.openWrite();
      try {
        for (final c in chunks) {
          await for (final chunk in c.file!.openRead()) {
            sink.add(chunk);
          }
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close();
        rethrow;
      }
      item.filePath = target.path;
      item.state = DlState.done;
      item.progress = 1;
      notifyListeners();
      unawaited(_finish(item, target));
    } catch (e) {
      item.state = DlState.failed;
      item.error = e.toString();
      notifyListeners();
    } finally {
      try {
        await partDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// A 429/503, or a 403 that GitHub uses for rate limiting.
  static bool _isRateLimit(int status, http.StreamedResponse r) {
    if (status == 429 || status == 503) return true;
    if (status == 403) {
      if (r.headers['x-ratelimit-remaining'] == '0') return true;
      if (r.headers.containsKey('retry-after')) return true;
    }
    return false;
  }

  /// How long to wait before retrying, from `Retry-After` / `X-RateLimit-Reset`.
  static Duration _retryAfter(http.StreamedResponse r) {
    final ra = r.headers['retry-after'];
    if (ra != null) {
      final s = int.tryParse(ra.trim());
      if (s != null) return Duration(seconds: s.clamp(1, _maxCoolDown.inSeconds));
    }
    final reset = r.headers['x-ratelimit-reset'];
    if (reset != null) {
      final epoch = int.tryParse(reset.trim());
      if (epoch != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(epoch * 1000)
            .difference(DateTime.now());
        if (d.inSeconds > 0) {
          return Duration(seconds: d.inSeconds.clamp(1, _maxCoolDown.inSeconds));
        }
      }
    }
    return const Duration(seconds: 5);
  }

  /// Exponential back-off with a little jitter, capped at 15s.
  static Duration _backoff(int attempts) {
    final ms = (800 * math.pow(2, attempts)).toInt() +
        math.Random().nextInt(400);
    return Duration(milliseconds: ms > 15000 ? 15000 : ms);
  }

  /// Final on-disk name. Actions artifacts are zip archives whose GitHub name
  /// carries no extension, so add one.
  static String _desiredFileName(String key, String name) {
    var safe = name.replaceAll('/', '_');
    if (key.startsWith('act-') && p.extension(safe).isEmpty) {
      safe = '$safe.zip';
    }
    return safe;
  }

  Future<File> _targetFile(Directory dir, DownloadItem item) =>
      _uniqueFile(dir, _desiredFileName(item.id, item.name));

  /// Mark a transfer done, then unpack an Actions artifact archive if the user
  /// has auto-unzip on. A lone payload file is moved next to the archive (so an
  /// app can open it directly); a multi-file archive becomes a sibling folder
  /// and the user is asked whether to open it.
  Future<void> _finish(DownloadItem item, File file) async {
    final result = await _processArtifact(item.id, file);
    if (result.file != null) {
      item.filePath = result.file!.path;
      notifyListeners();
    } else if (result.folder != null) {
      item.filePath = result.folder!.path;
      notifyListeners();
      _offerOpenFolder(result.folder!);
    }
  }

  /// Outcome of unpacking a downloaded artifact archive.
  static const _notApplicable = _UnzipResult(null, null);

  /// Unpack `file`; a failure simply leaves the original `.zip`.
  static Future<_UnzipResult> _processArtifact(String key, File file) async {
    if (!key.startsWith('act-')) return _notApplicable;
    if (!SettingsStore.i.autoUnzipArtifacts) return _notApplicable;
    if (p.extension(file.path).toLowerCase() != '.zip') return _notApplicable;

    final parent = file.parent;
    final base = p.basenameWithoutExtension(file.path);
    // Extract into a hidden staging folder first so the payload can be counted
    // before deciding between a single file and a folder.
    final staging = Directory(p.join(
        parent.path, '.ghnew-unzip-${DateTime.now().microsecondsSinceEpoch}'));
    try {
      await staging.create(recursive: true);
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final written = <String>[];
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = _sanitize(entry.name);
        if (name.isEmpty || name.contains('__MACOSX')) continue;
        final out = File(p.join(staging.path, name));
        await out.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>);
        written.add(name);
      }

      if (written.length == 1) {
        final only = File(p.join(staging.path, written.first));
        final dest = await _uniqueFile(parent, p.basename(written.first));
        try {
          await only.rename(dest.path);
          await staging.delete(recursive: true);
          return _UnzipResult(dest, null);
        } catch (_) {
          // Moving the lone file failed; keep the whole folder instead.
        }
      }
      final dest = await _uniqueDirectory(parent, base);
      await staging.rename(dest.path);
      return _UnzipResult(null, dest);
    } catch (_) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
      return _notApplicable;
    }
  }

  /// Ask whether to open the folder a multi-file artifact was unpacked into.
  static void _offerOpenFolder(Directory dir) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(L.str('unzipDoneTitle')),
        content: Text('${L.str('unzipFolderMessage')}\n\n${dir.path}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text(L.str('cancel'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(dctx);
              _openFolder(dir.path);
            },
            child: Text(L.str('openFolder')),
          ),
        ],
      ),
    );
  }

  /// Reveal a folder in the OS file manager. Android/iOS expose no generic
  /// folder viewer, so the dialog's path text is all those platforms get.
  static Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  /// Drop `.`/`..` components so a crafted entry can never escape `dest`.
  static String _sanitize(String name) => name
      .split('/')
      .where((s) => s.isNotEmpty && s != '.' && s != '..')
      .join('/');

  /// A non-existing folder next to the archive, appending " (n)" if needed.
  static Future<Directory> _uniqueDirectory(Directory parent, String name) async {
    var candidate = Directory(p.join(parent.path, name));
    var counter = 1;
    while (await candidate.exists()) {
      candidate = Directory(p.join(parent.path, '$name (${counter++})'));
    }
    return candidate;
  }

  /// Never clobber an existing file: append " (n)" until the name is free.
  static Future<File> _uniqueFile(Directory dir, String fileName) async {
    final ext = p.extension(fileName);
    final base = p.basenameWithoutExtension(fileName);
    var target = p.join(dir.path, fileName);
    var counter = 1;
    while (await File(target).exists()) {
      target = p.join(dir.path, '$base (${counter++})$ext');
    }
    return File(target);
  }

  /// Present a finished download: open a folder, or share a file so an installed
  /// app can open it.
  Future<void> reveal(DownloadItem item) async {
    final path = item.filePath;
    if (path == null) return;
    if (await Directory(path).exists()) {
      await _openFolder(path);
      return;
    }
    final f = File(path);
    if (!await f.exists()) return;
    await Share.shareXFiles([XFile(path)]);
  }

  static String bytesString(int? bytes) {
    if (bytes == null || bytes < 0) return '';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}

/// A single payload file, a sibling folder of several, or nothing to unpack.
class _UnzipResult {
  final File? file;
  final Directory? folder;
  const _UnzipResult(this.file, this.folder);
}

/// One contiguous byte range of a chunked download.
class _Chunk {
  final int start;
  final int end;
  int attempts = 0;
  int rateLimitEvents = 0;
  File? file;
  _Chunk(this.start, this.end);
}

/// A chunk queued to retry once `readyAt` passes.
class _Waiting {
  final int index;
  final DateTime readyAt;
  _Waiting(this.index, this.readyAt);
}

/// A non-206 chunk response: the server ignored our Range or returned an error.
class _HttpException implements Exception {
  final int status;
  _HttpException(this.status);
  @override
  String toString() => 'HTTP $status';
}