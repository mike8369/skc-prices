import 'package:meta/meta.dart';

// 병원 홈페이지 이벤트 가격 (tool/prices 수집기가 만든 prices.json).
// JSON에는 홈페이지에 적힌 사실(이름·가격·기간·지점)만 담고,
// 시술 찾기·단위·조건은 앱에서 읽을 때 계산한다 (시술 사전이 늘면 바로 반영되도록).

/// 수집하는 병원 체인.
enum PriceChain {
  ppeum('예쁨주의쁨의원', '예쁨주의쁨'),
  uni('유앤아이의원', '유앤아이'),
  velyb('블리비의원', '블리비');

  const PriceChain(this.label, this.shortLabel);
  final String label;
  final String shortLabel;

  static PriceChain? byName(String name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// 지점 홈페이지 하나를 읽은 결과.
@immutable
class PriceSource {
  const PriceSource({
    required this.chain,
    required this.branch,
    required this.url,
    required this.count,
    this.region,
  });

  final PriceChain chain;
  final String branch;

  /// 지역 ([priceRegions] 중 하나). 모르면 null.
  final String? region;

  /// 가격을 읽은 페이지 (앱의 '홈페이지에서 확인' 링크).
  final String url;
  final int count;

  Map<String, Object?> toJson() => {
    'chain': chain.name,
    'branch': branch,
    'url': url,
    'count': count,
    if (region != null) 'region': region,
  };

  static PriceSource? fromJson(Map<String, Object?> j) {
    final chain = PriceChain.byName(j['chain'] as String? ?? '');
    if (chain == null) return null;
    return PriceSource(
      chain: chain,
      branch: j['branch'] as String,
      url: j['url'] as String,
      count: (j['count'] as num?)?.toInt() ?? 0,
      region: j['region'] as String?,
    );
  }
}

/// 홈페이지에 적힌 이벤트 상품 하나. 같은 체인에서 이름·가격이 같으면 지점을 묶는다.
@immutable
class EventPrice {
  const EventPrice({
    required this.chain,
    required this.title,
    required this.price,
    required this.branches,
    this.group,
    this.originalPrice,
    this.endsAt,
  });

  final PriceChain chain;

  /// 상품 이름. 예: '울트라인 100샷 1회 체험가'
  final String title;

  /// 이벤트나 묶음 이름. 예: '브랜드 10주년 기념, 무한 페스타', '남성 얼굴 제모(아포지 플러스)'
  final String? group;
  final int price;

  /// 홈페이지에 함께 적힌 원래 가격.
  final int? originalPrice;

  /// 이벤트 마감일. 상시 이벤트면 null.
  final DateTime? endsAt;

  /// 이 가격으로 올라와 있는 지점 이름들.
  final List<String> branches;

  /// 지점을 빼고 같은 상품인지 가르는 열쇠.
  String get key =>
      '${chain.name}|${group ?? ''}|$title|$price|${originalPrice ?? ''}';

  EventPrice withBranches(List<String> branches) => EventPrice(
    chain: chain,
    title: title,
    price: price,
    branches: branches,
    group: group,
    originalPrice: originalPrice,
    endsAt: endsAt,
  );

  Map<String, Object?> toJson() => {
    'chain': chain.name,
    'title': title,
    if (group != null) 'group': group,
    'price': price,
    if (originalPrice != null) 'originalPrice': originalPrice,
    if (endsAt != null) 'endsAt': _date(endsAt!),
    'branches': branches,
  };

  static EventPrice? fromJson(Map<String, Object?> j) {
    final chain = PriceChain.byName(j['chain'] as String? ?? '');
    final price = (j['price'] as num?)?.toInt();
    if (chain == null || price == null) return null;
    final ends = j['endsAt'] as String?;
    return EventPrice(
      chain: chain,
      title: j['title'] as String,
      group: j['group'] as String?,
      price: price,
      originalPrice: (j['originalPrice'] as num?)?.toInt(),
      endsAt: ends == null ? null : DateTime.tryParse(ends),
      branches: [
        for (final b in j['branches'] as List? ?? const []) b as String,
      ],
    );
  }
}

/// 지역 이름과 순서. 수집기가 지점마다 이 중 하나를 붙인다.
const priceRegions = ['서울', '경기·인천', '강원', '충청', '전라', '경상', '제주'];

/// 병원 홈페이지의 지역 이름('서울권', '경기·인천권', '울산/경상' …)을 [priceRegions] 중 하나로.
String? normalizeRegion(String label) {
  final s = label.replaceAll(RegExp(r'[\s권]'), '');
  if (s.contains('서울')) return '서울';
  if (s.contains('경기') || s.contains('인천')) return '경기·인천';
  if (s.contains('강원')) return '강원';
  if (s.contains('충청') || s.contains('대전') || s.contains('세종')) return '충청';
  if (s.contains('전라') || s.contains('광주')) return '전라';
  if (s.contains('경상') ||
      s.contains('부산') ||
      s.contains('대구') ||
      s.contains('울산')) {
    return '경상';
  }
  if (s.contains('제주')) return '제주';
  return null;
}

/// 수집 결과 전체.
@immutable
class PriceFeed {
  const PriceFeed({
    required this.generatedAt,
    required this.sources,
    required this.items,
  });

  static const version = 1;

  final DateTime generatedAt;
  final List<PriceSource> sources;
  final List<EventPrice> items;

  static final empty = PriceFeed(
    generatedAt: DateTime(2000),
    sources: const [],
    items: const [],
  );

  bool get isEmpty => items.isEmpty;

  /// [chain] [branch]의 홈페이지 주소.
  String? urlOf(PriceChain chain, String branch) {
    for (final s in sources) {
      if (s.chain == chain && s.branch == branch) return s.url;
    }
    return null;
  }

  /// [chain] [branch]의 지역.
  String? regionOf(PriceChain chain, String branch) {
    for (final s in sources) {
      if (s.chain == chain && s.branch == branch) return s.region;
    }
    return null;
  }

  /// 지점이 있는 지역 ([priceRegions] 순서).
  List<String> get regions => [
    for (final r in priceRegions)
      if (sources.any((s) => s.region == r)) r,
  ];

  Map<String, Object?> toJson() => {
    'version': version,
    'generatedAt': generatedAt.toIso8601String(),
    'sources': [for (final s in sources) s.toJson()],
    'items': [for (final i in items) i.toJson()],
  };

  /// 모르는 버전이거나 깨진 내용이면 null.
  static PriceFeed? fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != version) {
      return null;
    }
    final generated = DateTime.tryParse(json['generatedAt'] as String? ?? '');
    if (generated == null) return null;
    return PriceFeed(
      generatedAt: generated,
      sources: [
        for (final s in json['sources'] as List? ?? const [])
          ?PriceSource.fromJson((s as Map).cast()),
      ],
      items: [
        for (final i in json['items'] as List? ?? const [])
          ?EventPrice.fromJson((i as Map).cast()),
      ],
    );
  }
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
