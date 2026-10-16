import 'dart:convert';
import 'dart:io';

import 'package:skc_prices/collector.dart';
import 'package:skc_prices/skc_prices.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

EventPrice item(
  String title,
  int price, {
  List<String> branches = const ['강남점'],
}) => EventPrice(
  chain: PriceChain.uni,
  title: title,
  price: price,
  branches: branches,
);

void main() {
  group('예쁨주의쁨 홈페이지', () {
    const branch = Branch(
      PriceChain.ppeum,
      '잠실점',
      'https://jamsil.ppeum.com/selectSurgery',
      region: '서울',
    );
    final items = const PpeumSource().parse(
      fixture('ppeum_select_surgery.html'),
      branch,
    );

    test('이벤트 상품 이름·가격·원래 가격·이벤트 이름', () {
      expect(items.map((i) => i.title), [
        '피코토닝 1회 한정가',
        '울트라인 100샷 1회 체험가',
        '포텐자 1회 체험가 (팁 미포함)',
      ]);
      expect(items.map((i) => i.price), [9900, 249000, 59000]);
      expect(items.map((i) => i.originalPrice), [19500, 350000, null]);
      expect(items.first.group, '브랜드 10주년 기념, 무한 페스타');
      expect(items.first.branches, ['잠실점']);
    });

    test('마감일: 9999-12-31은 상시 진행', () {
      expect(items[0].endsAt, DateTime(2026, 11, 3));
      expect(items[1].endsAt, isNull);
    });

    test('지점마다 지역이 있다', () async {
      final branches = await const PpeumSource().branches((_) async => '');
      expect(branches.every((b) => b.region != null), isTrue);
    });
  });

  group('유앤아이 홈페이지', () {
    final html = fixture('uni_home.html');

    test('지점 메뉴에서 지점 홈페이지와 지역을 찾는다', () async {
      final branches = await const UniSource().branches((_) async => html);
      expect(branches.map((b) => b.name), ['강남점', '선릉점']);
      expect(branches.last.url, 'https://www.sluni114.co.kr/');
      expect(branches.map((b) => b.region), ['서울', '서울']);
    });

    test('이벤트 카드: 묶음 이름과 상품 이름, 가격 없는 카드는 건너뛴다', () {
      final items = const UniSource().parse(
        html,
        const Branch(PriceChain.uni, '강남점', 'https://www.uni114.co.kr/'),
      );
      expect(items.map((i) => (i.group, i.title, i.price, i.originalPrice)), [
        ('리톡스 이벤트', '리톡스 Basic (리바이브 1cc + 독일산 스킨보톡스 나비존)', 440000, 629500),
        ('기미/잡티/홍조', '첫방문고객) 피코토닝 1회 체험가', 29000, 50000),
        ('LDM', 'LDM 10회', 400000, 700000),
      ]);
    });
  });

  group('블리비 홈페이지', () {
    final html = fixture('velyb_board.html');

    test('지점 탭에서 지점과 지역 (문 닫은 지점은 뺀다)', () async {
      final branches = await const VelybSource().branches((_) async => html);
      expect(branches.map((b) => (b.name, b.region)), [
        ('강남역점', '서울'),
        ('부산 서면점', '경상'),
      ]);
      expect(
        branches.first.url,
        contains('etc5=%EA%B0%95%EB%82%A8%EC%97%AD%EC%A0%90'),
      );
    });

    test('이벤트 카드: 이벤트 이름·마감일·상품, 가격 없는 상품은 건너뛴다', () {
      final items = const VelybSource().parse(
        html,
        const Branch(PriceChain.velyb, '강남역점', 'u'),
      );
      expect(
        items.map(
          (i) => (i.group, i.title, i.price, i.originalPrice, i.endsAt),
        ),
        [
          (
            '메가세일 페스타',
            '♥️메가세일♥️온다 리프팅(고강도 극초단파) 10,000J 한정가',
            23000,
            45500,
            DateTime(2026, 10, 17),
          ),
          ('부위별 필러', '필러(국산 아띠에르) 1cc 체험가', 49000, 99000, null),
        ],
      );
    });

    test('여러 쪽을 읽다가 새 상품이 없으면 멈춘다', () async {
      final asked = <String>[];
      final items = await const VelybSource().parseAllPages(
        const Branch(PriceChain.velyb, '강남역점', 'u'),
        (url) async {
          asked.add(url);
          return url.endsWith('p=1') ? html : '<html></html>';
        },
      );
      expect(items, hasLength(2));
      expect(asked, hasLength(2));
    });
  });

  test('같은 상품은 지점을 모아 하나로', () {
    final merged = mergeBranches([
      item('LDM 1회', 50000),
      item('LDM 1회', 50000, branches: ['선릉점']),
      item('LDM 1회', 45000, branches: ['잠실점']),
    ]);
    expect(merged.map((m) => m.price), [50000, 45000]);
    expect(merged.map((m) => m.branches), [
      ['강남점', '선릉점'],
      ['잠실점'],
    ]);
  });

  test('지역 이름 맞추기', () {
    expect(normalizeRegion('서울권'), '서울');
    expect(normalizeRegion('경기·인천권'), '경기·인천');
    expect(normalizeRegion('대전/충청'), '충청');
    expect(normalizeRegion('울산/경상'), '경상');
    expect(normalizeRegion('전라권'), '전라');
    expect(normalizeRegion('해외'), isNull);
  });

  test('version 2: 이름·지점을 표로 줄여 저장하고 그대로 읽는다', () {
    final feed = PriceFeed(
      generatedAt: DateTime.utc(2026, 10, 16, 9),
      sources: const [
        PriceSource(
          chain: PriceChain.uni,
          branch: '강남점',
          url: 'a',
          count: 2,
          region: '서울',
        ),
        PriceSource(
          chain: PriceChain.velyb,
          branch: '부산 서면점',
          url: 'b',
          count: 1,
          region: '경상',
        ),
      ],
      items: [
        EventPrice(
          chain: PriceChain.uni,
          title: 'LDM 1회',
          group: 'LDM',
          price: 50000,
          originalPrice: 80000,
          branches: const ['강남점'],
        ),
        EventPrice(
          chain: PriceChain.velyb,
          title: 'LDM 1회',
          price: 45000,
          endsAt: DateTime(2026, 10, 31),
          branches: const ['부산 서면점'],
        ),
      ],
    );
    final json = feed.toJson();
    expect(json['version'], 2);
    expect(json['strings'], ['LDM 1회', 'LDM']);
    final back = PriceFeed.fromJson(jsonDecode(jsonEncode(json)))!;
    expect(back.items.map((i) => i.key), feed.items.map((i) => i.key));
    expect(back.items.last.endsAt, DateTime(2026, 10, 31));
    expect(back.items.last.chain, PriceChain.velyb);
    expect(back.items.first.originalPrice, 80000);
  });

  test('version 1 수집본도 읽는다', () {
    final v1 = {
      'version': 1,
      'generatedAt': '2026-10-16T00:00:00.000Z',
      'sources': [
        {'chain': 'uni', 'branch': '강남점', 'url': 'a', 'count': 1},
        {'chain': 'nope', 'branch': '어딘가', 'url': 'b', 'count': 1},
      ],
      'items': [
        {
          'chain': 'uni',
          'title': 'LDM 1회',
          'price': 50000,
          'branches': ['강남점'],
        },
      ],
    };
    final feed = PriceFeed.fromJson(v1)!;
    expect(feed.items.single.title, 'LDM 1회');
    expect(feed.sources, hasLength(1), reason: '모르는 체인은 뺀다');
  });

  test('JSON으로 저장하고 다시 읽는다', () {
    final feed = PriceFeed(
      generatedAt: DateTime.utc(2026, 10, 16, 9),
      sources: const [
        PriceSource(
          chain: PriceChain.uni,
          branch: '강남점',
          url: 'https://www.uni114.co.kr/',
          count: 1,
          region: '서울',
        ),
      ],
      items: [item('LDM 1회', 50000)],
    );
    final back = PriceFeed.fromJson(jsonDecode(jsonEncode(feed.toJson())))!;
    expect(back.generatedAt, feed.generatedAt);
    expect(back.items.single.key, feed.items.single.key);
    expect(back.urlOf(PriceChain.uni, '강남점'), 'https://www.uni114.co.kr/');
    expect(back.regions, ['서울']);
    expect(PriceFeed.fromJson({'version': 99}), isNull);
  });
}
