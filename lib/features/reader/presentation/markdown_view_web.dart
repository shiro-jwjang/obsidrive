import 'dart:js_interop';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;
import 'package:web/web.dart' as web;

import '../../../core/markdown_parser.dart';
import '../../vault/domain/vault_models.dart';
import 'markdown_view_stub.dart';

export 'markdown_view_stub.dart';

@override
Widget buildMarkdownView({
  required String markdown,
  required List<Note> notes,
  required WikilinkTapCallback onWikilinkTap,
}) {
  final processed = _preprocessWikilinks(markdown);
  final html = md.markdownToHtml(
    processed,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final resolvedHtml = _resolveWikilinkStyles(html, notes);

  return _HtmlMarkdownView(html: resolvedHtml, onWikilinkTap: onWikilinkTap);
}

String _preprocessWikilinks(String markdown) {
  return markdown.replaceAllMapped(RegExp(r'\[\[([^\]\r\n]+)\]\]'), (match) {
    final raw = match.group(1)!.trim();
    final parts = raw.split('|');
    final target = parts.first.trim();
    final display = parts.length > 1
        ? parts.sublist(1).join('|').trim()
        : target;
    final encoded = Uri.encodeComponent(target);
    return '[$display](wikilink://$encoded)';
  });
}

String _resolveWikilinkStyles(String html, List<Note> notes) {
  return html.replaceAllMapped(RegExp(r'href="wikilink://([^"]+)"'), (match) {
    final target = Uri.decodeComponent(match.group(1)!);
    final link = parseWikilinks('[[$target]]').single;
    final exists = resolveInVault(link, notes) != null;
    final cls = exists ? 'wikilink exists' : 'wikilink missing';
    return 'href="wikilink://${match.group(1)}" class="$cls"';
  });
}

// ---------------------------------------------------------------------------
// Single shared DOM container — reused across note changes (no route push)
// ---------------------------------------------------------------------------

const _containerId = '__obsidrive_content__';

class _HtmlMarkdownView extends StatefulWidget {
  const _HtmlMarkdownView({required this.html, required this.onWikilinkTap});

  final String html;
  final WikilinkTapCallback onWikilinkTap;

  @override
  State<_HtmlMarkdownView> createState() => _HtmlMarkdownViewState();
}

class _HtmlMarkdownViewState extends State<_HtmlMarkdownView> {
  web.HTMLDivElement? _container;

  @override
  void initState() {
    super.initState();
    _ensureContainer();
  }

  @override
  Widget build(BuildContext context) {
    // Flutter side is empty — real content lives in DOM
    return const SizedBox.shrink();
  }

  /// Get or create the shared DOM container.
  void _ensureContainer() {
    var container = web.document.getElementById(_containerId);
    if (container == null) {
      container = web.document.createElement('div') as web.HTMLDivElement;
      (container as web.HTMLDivElement).id = _containerId;
      _applyStyles(container);
      _attachListeners(container);
      web.document.body!.appendChild(container);
    }
    _container = container as web.HTMLDivElement;
    _injectContent(_container!, widget.html);
  }

  @override
  void dispose() {
    // Remove container when leaving reader screen entirely
    _container?.remove();
    _container = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HtmlMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.html != oldWidget.html && _container != null) {
      _injectContent(_container!, widget.html);
    }
  }

  void _applyStyles(web.HTMLDivElement el) {
    final s = el.style;
    s.position = 'fixed';
    s.top = '56px'; // AppBar height
    s.left = '0';
    s.width = '100%';
    s.height = 'calc(100vh - 56px)';
    s.overflow = 'auto';
    s.padding = '16px';
    s.boxSizing = 'border-box';
    s.zIndex = '100';
    s.setProperty('-webkit-user-select', 'text');
    s.setProperty('user-select', 'text');
    s.backgroundColor = '#ffffff';
  }

  void _injectContent(web.HTMLDivElement div, String bodyHtml) {
    final htmlContent = '''
<style>
  body, p, li, td, th { font-family: system-ui, -apple-system, 'Segoe UI', sans-serif; font-size: 16px; line-height: 1.7; color: #1a1a1a; }
  h1 { font-size: 1.8em; margin-top: 0.5em; margin-bottom: 0.4em; font-weight: 700; }
  h2 { font-size: 1.5em; margin-top: 1.2em; margin-bottom: 0.3em; font-weight: 600; border-bottom: 1px solid #e5e5e5; padding-bottom: 0.2em; }
  h3 { font-size: 1.25em; margin-top: 1em; margin-bottom: 0.3em; font-weight: 600; }
  h4, h5, h6 { font-size: 1em; margin-top: 0.8em; font-weight: 600; }
  p { margin: 0.6em 0; white-space: pre-line; }
  ul, ol { padding-left: 1.5em; margin: 0.5em 0; }
  li { margin: 0.2em 0; }
  a { color: #2563eb; text-decoration: none; }
  a:hover { text-decoration: underline; }
  a.wikilink.exists { color: #7c3aed; font-weight: 500; cursor: pointer; }
  a.wikilink.exists:hover { text-decoration: underline; }
  a.wikilink.missing { color: #9ca3af; cursor: help; }
  code { font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace; font-size: 0.9em; background: #f3f4f6; padding: 0.15em 0.4em; border-radius: 4px; }
  pre { background: #f8f9fa; border: 1px solid #e5e7eb; border-radius: 8px; padding: 12px 16px; overflow-x: auto; margin: 0.8em 0; }
  pre code { background: none; padding: 0; font-size: 0.85em; line-height: 1.5; }
  blockquote { border-left: 4px solid #d1d5db; margin: 0.8em 0; padding: 0.4em 16px; color: #6b7280; }
  blockquote p { margin: 0.3em 0; }
  table { border-collapse: collapse; width: 100%; margin: 0.8em 0; font-size: 0.95em; }
  th, td { border: 1px solid #e5e7eb; padding: 8px 12px; text-align: left; }
  th { background: #f9fafb; font-weight: 600; }
  tr:nth-child(even) { background: #fafafa; }
  img { max-width: 100%; height: auto; border-radius: 8px; margin: 0.5em 0; }
  hr { border: none; border-top: 1px solid #e5e7eb; margin: 1.5em 0; }
  input[type="checkbox"] { margin-right: 6px; }
</style>
$bodyHtml''';
    div.innerHTML = htmlContent.toJS;
  }

  void _attachListeners(web.HTMLDivElement div) {
    div.addEventListener(
      'click',
      ((web.Event event) {
        final target = event.target;
        if (target == null) return;

        web.Element? el = target as web.Element;
        while (el != null && el != div) {
          if (el.tagName == 'A') {
            final href = el.getAttribute('href') ?? '';
            if (href.startsWith('wikilink://')) {
              event.preventDefault();
              final linkTarget = Uri.decodeComponent(
                href.replaceFirst('wikilink://', ''),
              );
              widget.onWikilinkTap(linkTarget);
            }
            return;
          }
          el = el.parentElement;
        }
      }).toJS,
    );
  }
}
