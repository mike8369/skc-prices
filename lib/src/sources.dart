// 병원 홈페이지에서 이벤트 가격을 읽는 부분. 홈페이지 구조가 바뀌면 여기를 고친다.
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'event_price.dart';

/// 지점 홈페이지 하나.
class Branch {
  const Branch(this.chain, this.name, this.url, {this.region});

  final PriceChain chain;
  final String name;

  /// [priceRegions] 중 하나.
  final String? region;

  /// 가격이 있는 페이지.
  final String url;

  @override
  String toString() => '${chain.label} $name';
}

/// 수집하는 체인과 지점 목록을 찾는 방법.
abstract class ChainSource {
  PriceChain get chain;

  /// 지점 목록. [fetch]로 홈페이지를 읽어서 찾을 수 있다.
  Future<List<Branch>> branches(Future<String> Function(String url) fetch);

  /// 가격 페이지 HTML에서 이벤트 상품을 읽는다.
  List<EventPrice> parse(String body, Branch branch);
}

String _text(Element? e) =>
    (e?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

int? _won(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.parse(digits);
}

/// 예쁨주의쁨: 지점마다 하위 도메인이 있고, '시술예약/가격'(/selectSurgery)에
/// 이벤트 상품이 data-name·data-price·data-end 속성과 함께 들어 있다.
class PpeumSource implements ChainSource {
  const PpeumSource();

  /// 하위 도메인이 있는 지점 (2026-10 확인). 홈페이지에 지점 목록이 없어서 직접 관리한다.
  /// 노원·서울대입구·분당·범계·수원역·하남미사·대전·울산·안산점은 아직 예전 홈페이지
  /// (www.ppeumNN.com, 구조가 다름)만 있어서 1단계에서는 뺐다.
  /// myeongdong·busan·jeju는 다른 브랜드(쁨글로벌의원)라서 넣지 않는다.
  static const subdomains = {
    'sinnonhyeon': ('강남본점', '서울'),
    'konkukuniv': ('건대점', '서울'),
    'jamsil': ('잠실점', '서울'),
    'balsan': ('발산점', '서울'),
    'bucheon': ('부천점', '경기·인천'),
    'bupyeong': ('부평점', '경기·인천'),
    'cheonan': ('천안점', '충청'),
    'daegu': ('대구점', '경상'),
    'changwon': ('창원점', '경상'),
    'chuncheon': ('춘천점', '강원'),
  };

  @override
  PriceChain get chain => PriceChain.ppeum;

  @override
  Future<List<Branch>> branches(
    Future<String> Function(String url) fetch,
  ) async => [
    for (final MapEntry(key: sub, value: (name, region)) in subdomains.entries)
      Branch(
        chain,
        name,
        'https://$sub.ppeum.com/selectSurgery',
        region: region,
      ),
  ];

  @override
  List<EventPrice> parse(String body, Branch branch) {
    final doc = html.parse(body);
    final items = <EventPrice>[];
    for (final input in doc.querySelectorAll(
      'input[data-fir="event"][data-price]',
    )) {
      final title = input.attributes['data-name']?.trim();
      final price = _won(input.attributes['data-price'] ?? '');
      if (title == null || title.isEmpty || price == null) continue;

      // 같은 상품 칸의 가격 상자: <span>판매가</span><span class="priceDecoration">원래 가격</span>
      final item = input.parent?.parent;
      final original = _won(_text(item?.querySelector('.priceDecoration')));
      final label = _text(item?.querySelector('label'));
      final group = RegExp(r'^\[([^\]]+)\]').firstMatch(label)?.group(1);
      final end = DateTime.tryParse(input.attributes['data-end'] ?? '');

      items.add(
        EventPrice(
          chain: chain,
          title: title,
          group: group,
          price: price,
          originalPrice: original == null || original <= price
              ? null
              : original,
          // 9999-12-31은 상시 진행
          endsAt: end == null || end.year >= 9999
              ? null
              : DateTime(end.year, end.month, end.day),
          branches: [branch.name],
        ),
      );
    }
    return items;
  }
}

/// 유앤아이: 지점마다 도메인이 따로 있고(www.○○uni114.co.kr), 첫 화면에
/// 이벤트 카드(.price_box: 묶음 이름·상품 이름·원래 가격·할인가)가 들어 있다.
/// 지점 목록은 첫 화면 상단의 '유앤아이 네트워크' 메뉴(data-domain)에 있다.
class UniSource implements ChainSource {
  const UniSource();

  static const home = 'https://www.uni114.co.kr/';

  @override
  PriceChain get chain => PriceChain.uni;

  @override
  Future<List<Branch>> branches(
    Future<String> Function(String url) fetch,
  ) async {
    final doc = html.parse(await fetch(home));
    final found = <Branch>[];
    // <li><p class="location">서울권</p><ul class="list"><li><a data-domain=…>강남점</a> …
    for (final a in doc.querySelectorAll('a[data-domain]')) {
      final name = _text(a);
      if (!name.endsWith('점')) continue;
      Element? group = a.parent;
      while (group != null && group.querySelector('.location') == null) {
        group = group.parent;
      }
      found.add(
        Branch(
          chain,
          name,
          'https://${a.attributes['data-domain']!.trim()}/',
          region: normalizeRegion(_text(group?.querySelector('.location'))),
        ),
      );
    }
    return found;
  }

  @override
  List<EventPrice> parse(String body, Branch branch) {
    final doc = html.parse(body);
    final items = <EventPrice>[];
    for (final box in doc.querySelectorAll('li.price_box')) {
      final group = _text(box.querySelector('.prd_text'));
      final info = _text(box.querySelector('.prd_info'));
      final price = _won(_text(box.querySelector('.discount .num')));
      final original = _won(_text(box.querySelector('.origin .num')));
      final title = info.isEmpty ? group : info;
      if (title.isEmpty || price == null) continue;
      items.add(
        EventPrice(
          chain: chain,
          title: title,
          group: group.isEmpty || group == title ? null : group,
          price: price,
          originalPrice: original == null || original <= price
              ? null
              : original,
          branches: [branch.name],
        ),
      );
    }
    return items;
  }
}

const sources = <ChainSource>[PpeumSource(), UniSource()];

/// 같은 체인에서 이름·가격이 같은 상품은 지점을 모아 하나로 만든다.
List<EventPrice> mergeBranches(List<EventPrice> items) {
  final merged = <String, EventPrice>{};
  for (final item in items) {
    final prev = merged[item.key];
    merged[item.key] = prev == null
        ? item
        : prev.withBranches([
            ...prev.branches,
            for (final b in item.branches)
              if (!prev.branches.contains(b)) b,
          ]);
  }
  return merged.values.toList();
}
