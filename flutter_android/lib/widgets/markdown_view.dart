import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Renders release changelog markdown (port of MarkdownView.swift).
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.markdown});
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.fontSize ?? 13.0;
    final sheet = MarkdownStyleSheet(
      p: TextStyle(fontSize: base, height: 1.35, color: T.text),
      strong: TextStyle(fontWeight: FontWeight.bold, color: T.text),
      em: const TextStyle(fontStyle: FontStyle.italic),
      emStrong: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
      code: TextStyle(
          fontSize: base - 1,
          fontFamily: 'monospace',
          color: T.codeText,
          backgroundColor: T.codeBg),
      codeblockDecoration: BoxDecoration(color: T.codeBg, borderRadius: BorderRadius.circular(6)),
      codeblockPadding: const EdgeInsets.all(8),
      blockquoteDecoration: BoxDecoration(
          color: T.codeBg,
          border: const Border(left: BorderSide(color: Color(0xFF3A4150))),
          borderRadius: BorderRadius.circular(4)),
      blockquote: TextStyle(color: T.text2, fontStyle: FontStyle.italic),
      h1: TextStyle(fontSize: base + 5, fontWeight: FontWeight.bold, color: T.text),
      h2: TextStyle(fontSize: base + 3, fontWeight: FontWeight.bold, color: T.text),
      h3: TextStyle(fontSize: base + 1, fontWeight: FontWeight.bold, color: T.text),
      h4: TextStyle(fontSize: base, fontWeight: FontWeight.bold, color: T.text),
      h5: TextStyle(fontSize: base, fontWeight: FontWeight.bold, color: T.text),
      h6: TextStyle(fontSize: base, fontWeight: FontWeight.bold, color: T.text),
      a: TextStyle(color: T.branchText, decoration: TextDecoration.underline),
      listBullet: TextStyle(height: 1.35, color: T.text),
      listIndent: 20.0,
      horizontalRuleDecoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF9AA1AB)))),
      blockSpacing: 6.0,
    );
    return MarkdownBody(
      data: markdown,
      selectable: true,
      styleSheet: sheet,
      onTapLink: (text, href, title) {
        final h = href;
        if (h != null) launchExternal(h);
      },
    );
  }
}

/// Opens a URL in the system browser.
Future<void> launchExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {}
}