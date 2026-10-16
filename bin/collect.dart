// 병원 홈페이지 이벤트 가격 수집기.
//
//   dart run bin/collect.dart --out out                          # out/prices.json, out/status.json
//   dart run bin/collect.dart --out out --previous old.json      # 실패한 체인은 지난 수집본으로 채운다
//   dart run bin/collect.dart --out out --only uni --max-branches 2   # 시험 삼아 조금만
//
// 종료 코드: 0 정상, 1 아무것도 못 모음(저장하지 않음), 3 일부 체인 실패(지난 값으로 채워 저장함).
import 'dart:convert';
import 'dart:io';

import 'package:skc_prices/collector.dart';
import 'package:skc_prices/skc_prices.dart';

/// 수집하지 않는 지점 ('체인:지점'). 병원이 빼 달라고 하면 여기에 넣는다. 예: 'uni:강남점'
const excludedBranches = <String>{};

Future<void> main(List<String> args) async {
  final outDir = Directory(_arg(args, '--out') ?? 'out');
  final only = _arg(args, '--only');
  final maxBranches = int.tryParse(_arg(args, '--max-branches') ?? '');
  final previous = _loadPrevious(_arg(args, '--previous'));

  final fetcher = PoliteFetcher();
  final sourcesOut = <PriceSource>[];
  final items = <EventPrice>[];
  final warnings = <String>[];
  final chains = <String, Map<String, Object?>>{};

  for (final source in sources) {
    if (only != null && source.chain.name != only) continue;
    final chainItems = <EventPrice>[];
    final chainSources = <PriceSource>[];
    final failed = <String>[];
    try {
      var branches = [
        for (final b in await source.branches(fetcher.get))
          if (!excludedBranches.contains('${b.chain.name}:${b.name}')) b,
      ];
      if (maxBranches != null) branches = branches.take(maxBranches).toList();
      stdout.writeln('${source.chain.label}: 지점 ${branches.length}곳');
      for (final branch in branches) {
        try {
          final found = source.parse(await fetcher.get(branch.url), branch);
          stdout.writeln('  ${branch.name}: ${found.length}개');
          if (found.isEmpty) {
            failed.add('${branch.name}: 상품 0개 (홈페이지 구조가 바뀌었을 수 있음)');
            continue;
          }
          chainItems.addAll(found);
          chainSources.add(
            PriceSource(
              chain: source.chain,
              branch: branch.name,
              url: branch.url,
              count: found.length,
              region: branch.region,
            ),
          );
        } on Object catch (e) {
          failed.add('${branch.name}: $e');
        }
      }
    } on Object catch (e) {
      failed.add('지점 목록: $e');
    }

    // 체인 전체를 못 읽었으면 지난 수집본으로 채운다 (앱에서 갑자기 사라지지 않게).
    var reused = false;
    if (chainItems.isEmpty && previous != null) {
      chainItems.addAll(previous.items.where((i) => i.chain == source.chain));
      chainSources.addAll(
        previous.sources.where((s) => s.chain == source.chain),
      );
      reused = chainItems.isNotEmpty;
    }
    if (failed.isNotEmpty || reused) {
      warnings.add(
        '${source.chain.label}: 실패 ${failed.length}곳${reused ? ' (지난 수집본 사용)' : ''}',
      );
    }
    chains[source.chain.name] = {
      'branches': chainSources.length,
      'items': chainItems.length,
      'failed': failed,
      'reusedPrevious': reused,
    };
    items.addAll(chainItems);
    sourcesOut.addAll(chainSources);
  }
  fetcher.close();

  final feed = PriceFeed(
    generatedAt: DateTime.now().toUtc(),
    sources: sourcesOut,
    items: mergeBranches(items),
  );
  if (feed.isEmpty) {
    stderr.writeln('모은 상품이 없어서 저장하지 않았어요.');
    exitCode = 1;
    return;
  }

  outDir.createSync(recursive: true);
  final pricesFile = File('${outDir.path}/prices.json')
    ..writeAsStringSync(jsonEncode(feed.toJson()));
  final status = {
    'generatedAt': feed.generatedAt.toIso8601String(),
    'branches': feed.sources.length,
    'items': feed.items.length,
    'sizeKB': (pricesFile.lengthSync() / 1024).round(),
    'chains': chains,
    'warnings': warnings,
  };
  File(
    '${outDir.path}/status.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(status));

  stdout
    ..writeln()
    ..writeln('저장: ${pricesFile.path} (${status['sizeKB']}KB)')
    ..writeln('지점 ${feed.sources.length}곳, 상품 ${feed.items.length}개');
  for (final w in warnings) {
    stdout.writeln('경고: $w');
  }
  if (warnings.isNotEmpty) exitCode = 3;
}

PriceFeed? _loadPrevious(String? path) {
  if (path == null) return null;
  try {
    return PriceFeed.fromJson(jsonDecode(File(path).readAsStringSync()));
  } on Object {
    return null;
  }
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}
