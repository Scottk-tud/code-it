import 'package:flutter/painting.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/haskell.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// Dateiendung → Hervorhebung. Deckt die Sprachen ab, die die TU-Instanz für
/// Programmieraufgaben anbietet (`programmingLanguageFeatures`).
const _nachEndung = <String, String>{
  'java': 'java',
  'py': 'python',
  'c': 'c',
  'h': 'c',
  'cpp': 'cpp',
  'cc': 'cpp',
  'hpp': 'cpp',
  'cs': 'csharp',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'swift': 'swift',
  'js': 'javascript',
  'mjs': 'javascript',
  'ts': 'typescript',
  'rs': 'rust',
  'go': 'go',
  'sh': 'bash',
  'bash': 'bash',
  'rb': 'ruby',
  'dart': 'dart',
  'hs': 'haskell',
  'r': 'r',
  'xml': 'xml',
  'html': 'xml',
  'json': 'json',
  'md': 'markdown',
  'yml': 'yaml',
  'yaml': 'yaml',
  'gradle': 'kotlin',
};

final Map<String, Mode> _modi = {
  'java': langJava,
  'python': langPython,
  'c': langC,
  'cpp': langCpp,
  'csharp': langCsharp,
  'kotlin': langKotlin,
  'swift': langSwift,
  'javascript': langJavascript,
  'typescript': langTypescript,
  'rust': langRust,
  'go': langGo,
  'bash': langBash,
  'ruby': langRuby,
  'dart': langDart,
  'haskell': langHaskell,
  'r': langR,
  'xml': langXml,
  'json': langJson,
  'markdown': langMarkdown,
  'yaml': langYaml,
  'plaintext': langPlaintext,
};

String spracheFuer(String pfad) {
  final name = pfad.split('/').last.toLowerCase();
  if (name == 'makefile') return 'bash';
  final punkt = name.lastIndexOf('.');
  if (punkt < 0) return 'plaintext';
  return _nachEndung[name.substring(punkt + 1)] ?? 'plaintext';
}

CodeHighlightTheme hervorhebung(String pfad, Map<String, TextStyle> thema) {
  final sprache = spracheFuer(pfad);
  return CodeHighlightTheme(
    languages: {sprache: CodeHighlightThemeMode(mode: _modi[sprache]!)},
    theme: thema,
  );
}

/// Zeichen für `Strg+/`. Python, Bash, R, Ruby und YAML kommentieren mit `#`.
String kommentarZeichen(String pfad) => switch (spracheFuer(pfad)) {
  'python' || 'bash' || 'r' || 'ruby' || 'yaml' => '#',
  'haskell' => '--',
  _ => '//',
};

/// Paare, die beim Tippen ergänzt werden.
const klammerPaare = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};
