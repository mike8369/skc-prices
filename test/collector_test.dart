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
