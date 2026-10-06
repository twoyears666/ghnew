import 'dart:async';
import 'dart:io';

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

  Future<void> _runChunks(DownloadItem item, String url, String? token,
      int total, int level, File target) async {
    final safeKey = item.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final partDir = await Directory(
            p.join(Directory.systemTemp.path, 'ghnew_parts_$safeKey'))
        .create(recursive: true);

    // Split [0, total) into `level` contiguous byte ranges.
    final chunkSize = (total / level).ceil();
    final ranges = <List<int>>[];
    var start = 0;
    while (start < total) {
      final end = (start + chunkSize - 1 < total - 1) ? start + chunkSize - 1 : total - 1;
      ranges.add([start, end]);
      start = end + 1;
    }

    final received = List<int>.filled(ranges.length, 0);
    final parts = List<File?>.filled(ranges.length, null);
    var failed = false;

    Future<void> one(int i) async {
      final s = ranges[i][0];
      final e = ranges[i][1];
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(url));
        req.headers.addAll(_headers(token));
        req.headers['Range'] = 'bytes=$s-$e';
        final resp = await client.send(req).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 206 && resp.statusCode != 200) {
          await resp.stream.drain<void>();
          throw Exception('HTTP ${resp.statusCode}');
        }
        final part = File(p.join(partDir.path, 'part_$i'));
        final sink = part.openWrite();
        try {
          await for (final chunk in resp.stream) {
            sink.add(chunk);
            received[i] += chunk.length;
            if (!failed) {
              final sum = received.fold<int>(0, (a, b) => a + b);
              item.progress = (sum / total).clamp(0.0, 1.0).toDouble();
              notifyListeners();
            }
          }
          await sink.flush();
          await sink.close();
        } catch (_) {
          await sink.close();
          rethrow;
        }
        parts[i] = part;
      } catch (err) {
        failed = true;
        rethrow;
      } finally {
        client.close();
      }
    }

    try {
      await Future.wait([for (var i = 0; i < ranges.length; i++) one(i)]);
      if (failed) throw Exception('Chunk download failed.');
      final sink = target.openWrite();
      for (final part in parts) {
        await for (final chunk in part!.openRead()) {
          sink.add(chunk);
        }
      }
      await sink.flush();
      await sink.close();
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