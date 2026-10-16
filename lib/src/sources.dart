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

/// 블리비: 지점마다 이벤트 게시판(/community/community01.php?tb=event_multi&etc5=지점)이 있고
/// 여러 쪽(p=1, 2, …)에 이벤트 카드(.boardList > ul > li)가 나뉘어 있다.
/// 카드: 이벤트 이름(.t01, 앞에 [지점]), 마감(.date 'YYYY-MM-DD까지'), 상품(.slist li: strong 이름,
/// .o_price01 판매가, .s_price01 del 원래 가격). 지점 목록은 같은 화면의 지점 탭(#tab_menu01_new)에 있다.
class VelybSource implements ChainSource {
  const VelybSource();

  static const site = 'https://m.velyb.kr';
  static const _board = '$site/community/community01.php?tb=event_multi';

  /// 한 지점에서 읽을 최대 쪽 수 (보통 4쪽 안팎).
  static const maxPages = 15;

  /// 지점 이름 → 지역. 홈페이지에는 지역 묶음이 없어서 직접 관리한다 (2026-10 확인).
  /// 새 지점이 생기면 지역이 비어서 수집 결과의 warnings에 나온다.
  static const regions = {
    '강남역점': '서울', '건대점': '서울', '구로점': '서울', '노원점': '서울', //
    '리저브 청담점': '서울', '명동점': '서울', '목동점': '서울', '발산점': '서울',
    '영등포점': '서울', '용산점': '서울', '왕십리점': '서울', '잠실점': '서울',
    '청량리점': '서울', '홍대점': '서울',
    '경기 광주점': '경기·인천', '광명점': '경기·인천', '구리점': '경기·인천',
    '김포점': '경기·인천', '동탄점': '경기·인천', '부천점': '경기·인천',
    '분당점': '경기·인천', '성남 모란점': '경기·인천', '수원점': '경기·인천',
    '수원 인계점': '경기·인천', '안산점': '경기·인천', '안양점': '경기·인천',
    '용인 수지점': '경기·인천', '의정부점': '경기·인천', '인천 구월점': '경기·인천',
    '인천 부평점': '경기·인천', '일산점': '경기·인천', '평택점': '경기·인천',
    '하남 미사점': '경기·인천', '시흥점': '경기·인천',
    '원주점': '강원', '춘천점': '강원',
    '대전점': '충청', '세종점': '충청', '천안점': '충청', '청주점': '충청',
    '광주점': '전라', '광주 첨단점': '전라', '순천점': '전라', '전주점': '전라',
    '경주점': '경상', '구미점': '경상', '김해점': '경상', '대구 동성로점': '경상',
    '마산점': '경상', '부산 경성대점': '경상', '부산 남포점': '경상',
    '부산 덕천점': '경상', '부산 서면점': '경상', '부산 센텀점': '경상',
    '양산점': '경상', '울산점': '경상', '진주점': '경상', '창원점': '경상',
    '포항점': '경상',
    '제주점': '제주',
  };

  static String branchUrl(String name, {int page = 1}) =>
      '$_board&act=list&etc5=${Uri.encodeQueryComponent(name)}&p=$page';

  @override
  PriceChain get chain => PriceChain.velyb;

  @override
  Future<List<Branch>> branches(
    Future<String> Function(String url) fetch,
  ) async {
    final doc = html.parse(await fetch(_board));
    final names = <String>{
      for (final a in doc.querySelectorAll('#tab_menu01_new li a'))
        if (_text(a).endsWith('점')) _text(a),
    };
    return [
      for (final name in names)
        Branch(chain, name, branchUrl(name), region: regions[name]),
    ];
  }

  /// 한 지점의 모든 쪽을 읽는다. 새 상품이 없는 쪽이 나오면 멈춘다.
  Future<List<EventPrice>> parseAllPages(
    Branch branch,
    Future<String> Function(String url) fetch,
  ) async {
    final all = <EventPrice>[];
    final seen = <String>{};
    for (var page = 1; page <= maxPages; page++) {
      final found = parse(
        await fetch(branchUrl(branch.name, page: page)),
        branch,
      );
      final fresh = [
        for (final i in found)
          if (seen.add(i.key)) i,
      ];
      if (fresh.isEmpty) break;
      all.addAll(fresh);
    }
    return all;
  }

  @override
  List<EventPrice> parse(String body, Branch branch) {
    final doc = html.parse(body);
    final items = <EventPrice>[];
    for (final card in doc.querySelectorAll('.boardList > ul > li')) {
      final group = _text(
        card.querySelector('.t01'),
      ).replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '');
      final date = RegExp(
        r'(\d{4})-(\d{2})-(\d{2})',
      ).firstMatch(_text(card.querySelector('.date')));
      final endsAt = date == null
          ? null
          : DateTime(
              int.parse(date[1]!),
              int.parse(date[2]!),
              int.parse(date[3]!),
            );
      for (final li in card.querySelectorAll('.slist > li')) {
        final title = _text(li.querySelector('strong'));
        final price = _won(_text(li.querySelector('.o_price01')));
        final original = _won(_text(li.querySelector('.s_price01')));
        if (title.isEmpty || price == null) continue;
        items.add(
          EventPrice(
            chain: chain,
            title: title,
            group: group.isEmpty ? null : group,
            price: price,
            originalPrice: original == null || original <= price
                ? null
                : original,
            endsAt: endsAt,
            branches: [branch.name],
          ),
        );
      }
    }
    return items;
  }
}

const sources = <ChainSource>[PpeumSource(), UniSource(), VelybSource()];

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
