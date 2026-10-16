import 'dart:convert';
import 'dart:io';

/// 병원 홈페이지를 천천히, robots.txt를 지키며 읽는다.
class PoliteFetcher {
  PoliteFetcher({
    this.userAgent = defaultUserAgent,
    this.pause = const Duration(seconds: 2),
  }) : _client = HttpClient()
         ..userAgent = userAgent
         ..connectionTimeout = const Duration(seconds: 20);

  /// 누가 왜 읽는지 병원이 알 수 있게 저장소 주소를 넣는다.
  static const defaultUserAgent =
      'SkcPriceBot/0.1 (+https://github.com/mike8369/skc-prices)';

  final String userAgent;

  /// 요청 사이에 쉬는 시간.
  final Duration pause;

  final HttpClient _client;
  final _robots = <String, List<String>>{};
  DateTime _last = DateTime(2000);

  Future<String> get(String url) async {
    final uri = Uri.parse(url);
    final disallowed = _robots[uri.host] ??= await _loadRobots(uri);
    if (disallowed.any((p) => p.isNotEmpty && uri.path.startsWith(p))) {
      throw StateError('robots.txt가 막은 주소: $url');
    }
    return _download(uri);
  }

  Future<String> _download(Uri uri) async {
    final wait = pause - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final res = await (await _client.getUrl(uri)).close();
    // 일부 병원 페이지에 깨진 글자가 섞여 있어서 그 글자만 건너뛴다.
    final body = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    return body;
  }

  /// User-agent: * 묶음의 Disallow 경로. 읽지 못하면 막힌 곳이 없다고 본다.
  Future<List<String>> _loadRobots(Uri site) async {
    try {
      final text = await _download(
        site.replace(path: '/robots.txt', query: ''),
      );
      final disallow = <String>[];
      var applies = false;
      for (final raw in const LineSplitter().convert(text)) {
        final line = raw.split('#').first.trim();
        final i = line.indexOf(':');
        if (i < 0) continue;
        final key = line.substring(0, i).trim().toLowerCase();
        final value = line.substring(i + 1).trim();
        if (key == 'user-agent') applies = value == '*';
        if (applies && key == 'disallow') disallow.add(value);
      }
      return disallow;
    } on Object {
      return const [];
    }
  }

  void close() => _client.close();
}
