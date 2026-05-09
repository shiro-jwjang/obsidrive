import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;
import 'package:web/web.dart' as web;

import '../../../core/markdown_parser.dart';
import '../../vault/data/vault_repository.dart' show BacklinkEntry;
import '../../vault/domain/vault_models.dart';
import 'markdown_view_stub.dart';

export 'markdown_view_stub.dart';

@override
Widget buildMarkdownView({
  required String markdown,
  required List<Note> notes,
  required WikilinkTapCallback onWikilinkTap,
  List<BacklinkEntry> backlinks = const [],
  BacklinkTapCallback? onBacklinkTap,
  Future<void> Function()? onRefresh,
}) {
  final hardBreaks = _convertSoftBreaks(markdown);
  final processed = _preprocessWikilinks(hardBreaks);
  final html = md.markdownToHtml(
    processed,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final resolvedHtml = _resolveWikilinkStyles(html, notes);

  return _HtmlMarkdownView(
    html: resolvedHtml,
    backlinks: backlinks,
    onWikilinkTap: onWikilinkTap,
    onBacklinkTap: onBacklinkTap,
    onRefresh: onRefresh,
  );
}

/// Convert single newlines (soft breaks) to markdown hard breaks (two trailing spaces).
/// Preserves paragraph breaks (double newlines) and code blocks.
String _convertSoftBreaks(String text) {
  final buffer = StringBuffer();
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    buffer.write(lines[i]);
    if (i < lines.length - 1) {
      final isBlank = lines[i].trimRight().isEmpty;
      final nextIsBlank =
          i + 1 < lines.length && lines[i + 1].trimRight().isEmpty;
      if (isBlank || nextIsBlank) {
        // Paragraph break — keep as-is
        buffer.writeln();
      } else {
        // Soft break — convert to hard break
        buffer.writeln('  ');
      }
    }
  }
  return buffer.toString();
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
  const _HtmlMarkdownView({
    required this.html,
    required this.backlinks,
    required this.onWikilinkTap,
    this.onBacklinkTap,
    this.onRefresh,
  });

  final String html;
  final List<BacklinkEntry> backlinks;
  final WikilinkTapCallback onWikilinkTap;
  final BacklinkTapCallback? onBacklinkTap;
  final Future<void> Function()? onRefresh;

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
    _registerRefreshBridge();
    _injectContent(_container!, widget.html);
    _attachPullToRefresh(_container!);
  }

  @override
  void dispose() {
    // Remove container when leaving reader screen entirely
    globalContext.setProperty('__obsidriveNoteRefresh'.toJS, null);
    _container?.remove();
    _container = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HtmlMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onRefresh != oldWidget.onRefresh) {
      _registerRefreshBridge();
    }
    if ((widget.html != oldWidget.html ||
            widget.backlinks != oldWidget.backlinks) &&
        _container != null) {
      _injectContent(_container!, widget.html);
      _attachPullToRefresh(_container!);
    } else if (_container != null) {
      _attachPullToRefresh(_container!);
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
    s.pointerEvents = 'auto';
    s.padding = '16px';
    s.boxSizing = 'border-box';
    s.zIndex = '100';
    s.overscrollBehavior = 'contain';
    s.setProperty('-webkit-user-select', 'text');
    s.setProperty('user-select', 'text');
    s.backgroundColor = '#ffffff';
  }

  void _injectContent(web.HTMLDivElement div, String bodyHtml) {
    final backlinksHtml = _buildBacklinksHtml(widget.backlinks);
    final htmlContent =
        '''
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
  .backlinks-section { margin-top: 32px; padding-top: 16px; border-top: 1px solid #333; }
  .backlinks-section h3 { font-size: 14px; color: #9ca3af; margin-bottom: 8px; }
  .backlinks-section a { display: block; padding: 4px 0; color: #7c3aed; cursor: pointer; text-decoration: none; }
  .backlinks-section a:hover { text-decoration: underline; }
</style>
<div
  data-obsidrive-ptr-indicator
  style="height:0;overflow:hidden;display:flex;align-items:flex-end;justify-content:center;color:#6b7280;font-size:14px;font-weight:500;transition:height 0.18s ease, opacity 0.18s ease;padding:0 0 0 0;opacity:0;"
></div>
$bodyHtml
$backlinksHtml''';
    div.innerHTML = htmlContent.toJS;
  }

  String _buildBacklinksHtml(List<BacklinkEntry> backlinks) {
    if (backlinks.isEmpty) {
      return '';
    }

    const escape = HtmlEscape(HtmlEscapeMode.element);
    final items = backlinks
        .map(
          (backlink) =>
              '''
<a
  href="#"
  class="wikilink exists"
  data-backlink-id="${backlink.sourceNoteId}"
  title="${escape.convert(backlink.sourceFilePath)}"
>${escape.convert(backlink.sourceTitle)}</a>''',
        )
        .join();

    return '''
<div class="backlinks-section">
  <h3>백링크 (${backlinks.length})</h3>
  $items
</div>''';
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
            final backlinkId = el.getAttribute('data-backlink-id');
            if (backlinkId != null) {
              event.preventDefault();
              BacklinkEntry? backlink;
              for (final entry in widget.backlinks) {
                if (entry.sourceNoteId.toString() == backlinkId) {
                  backlink = entry;
                  break;
                }
              }
              if (backlink != null) {
                widget.onBacklinkTap?.call(backlink);
              }
              return;
            }

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

  void _registerRefreshBridge() {
    JSPromise<JSAny?> refresh() {
      final handler = widget.onRefresh;
      if (handler == null) {
        return Future<void>.value().toJS;
      }
      return handler().toJS;
    }

    globalContext.setProperty('__obsidriveNoteRefresh'.toJS, refresh.toJS);
  }

  void _attachPullToRefresh(web.HTMLDivElement div) {
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.text =
        '''
(() => {
  const div = document.getElementById(${jsonEncode(_containerId)});
  if (!div) return;

  div.style.overscrollBehavior = 'contain';

  if (div.__obsidrivePtrAttached) {
    return;
  }
  div.__obsidrivePtrAttached = true;

  let startY = 0;
  let peakPull = 0;
  let isPulling = false;
  let isRefreshing = false;

  const getIndicator = () => div.querySelector('[data-obsidrive-ptr-indicator]');
  const setIndicator = (text, pull) => {
    const indicator = getIndicator();
    if (!indicator) return;
    const height = Math.max(0, Math.min(pull, 72));
    indicator.textContent = text;
    indicator.style.height = `\${height}px`;
    indicator.style.opacity = height > 0 ? '1' : '0';
    indicator.style.paddingBottom = height > 0 ? '10px' : '0';
  };
  const reset = () => {
    peakPull = 0;
    isPulling = false;
    setIndicator('', 0);
  };

  div.addEventListener('touchstart', (event) => {
    if (isRefreshing) return;
    startY = event.touches && event.touches.length ? event.touches[0].clientY : 0;
    peakPull = 0;
    isPulling = div.scrollTop === 0;
    if (isPulling) {
      setIndicator('↓ 더 아래로...', 0);
    }
  }, { passive: true });

  div.addEventListener('touchmove', (event) => {
    if (isRefreshing || !isPulling || div.scrollTop !== 0) return;
    const currentY = event.touches && event.touches.length ? event.touches[0].clientY : startY;
    const rawPull = currentY - startY;
    if (rawPull <= 0) {
      peakPull = 0;
      setIndicator('↓ 더 아래로...', 0);
      return;
    }

    const pull = Math.min(rawPull * 0.6, 96);
    peakPull = Math.max(peakPull, pull);
    setIndicator(
      pull >= 60 ? '↻ 놓으면 새로고침' : '↓ 더 아래로...',
      pull,
    );
  }, { passive: true });

  div.addEventListener('touchend', async () => {
    if (isRefreshing) return;

    if (peakPull >= 60 && typeof window.__obsidriveNoteRefresh === 'function') {
      isRefreshing = true;
      setIndicator('↻ 새로고침 중...', 60);
      try {
        await window.__obsidriveNoteRefresh();
      } finally {
        isRefreshing = false;
        reset();
      }
      return;
    }

    reset();
  }, { passive: true });

  div.addEventListener('touchcancel', () => {
    if (!isRefreshing) {
      reset();
    }
  }, { passive: true });
})();
''';
    div.appendChild(script);
    script.remove();
  }
}
