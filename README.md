# skc-prices

피부과 **공식 홈페이지**에 올라온 이벤트 가격을 매일 모으는 수집기와 공개 데이터.
스킨케어 기록 앱 **스크크**의 '이벤트 가격' 비교에 쓴다.

- 데이터: https://mike8369.github.io/skc-prices/prices.json
- 마지막 수집 결과: https://mike8369.github.io/skc-prices/status.json (저장소의 `status/last-run.json`에도 남는다)
- 수집: GitHub Actions가 매일 06:00(한국 시간)에 실행 → GitHub Pages로 배포 ([workflow](.github/workflows/collect.yml))

## 대상

| 체인 | 가격 페이지 | 지점 목록 |
|---|---|---|
| 예쁨주의쁨 | `https://<지점>.ppeum.com/selectSurgery`의 `input[data-fir=event]` | `PpeumSource.subdomains` (지점 이름·지역 직접 관리) |
| 유앤아이 | 지점 홈페이지 첫 화면의 `li.price_box` | 첫 화면 '유앤아이 네트워크' 메뉴의 `data-domain`, 지역은 메뉴의 '서울권' 같은 묶음 |
| 블리비 | `m.velyb.kr/community/community01.php?tb=event_multi&etc5=<지점>&p=<쪽>`의 이벤트 카드 | 같은 화면의 지점 탭, 지역은 `VelybSource.regions` (직접 관리) |

## 직접 돌리기

```sh
dart pub get
dart test
dart run bin/collect.dart --out out                               # out/prices.json, out/status.json
dart run bin/collect.dart --out out --only uni --max-branches 2   # 시험 수집
```

종료 코드: 0 정상, 1 아무것도 못 모음(저장 안 함), 3 일부 체인 실패(지난 수집본으로 채워 저장).
홈페이지 구조가 바뀌면 그 체인이 0개로 나오고 `status.json`의 `warnings`에 남는다.
`lib/src/sources.dart`를 고치고 `test/fixtures/`의 예시 HTML과 테스트를 함께 고친다.

## 데이터 모양 (`prices.json`, version 2)

상품마다 이름과 지점 이름을 되풀이하지 않도록 문자열 표와 배열로 줄였다 (version 1보다 4배쯤 작다).

```jsonc
{
  "version": 2,
  "generatedAt": "2026-10-16T21:00:00.000Z",
  "sources": [ { "chain": "uni", "branch": "강남점", "url": "https://www.uni114.co.kr/", "count": 418, "region": "서울" } ],
  "strings": [ "LDM 10회", "LDM" ],
  // [이름, 이벤트 이름(없으면 -1), 가격, 원래 가격(없으면 0), 마감 YYYYMMDD(없으면 0), 지점(sources 번호)…]
  "items": [ [0, 1, 400000, 700000, 0, 0] ]
}
```

- 같은 체인에서 이름·가격이 같은 상품은 지점을 모아 한 줄로 만든다.
- 시술 분류·단위(샷/cc/회)·조건(첫 방문/체험가 등)은 넣지 않는다. 앱이 자기 시술 사전으로 읽는다.
- 모양을 바꾸면 `PriceFeed.version`을 올린다. `PriceFeed.fromJson`은 1과 2를 모두 읽고, 모르는 체인의 지점은 건너뛴다.

## 지키는 것

- robots.txt를 지키고, 요청 사이에 2초씩 쉬며, 하루 한 번만 돌린다. User-Agent에 이 저장소 주소를 넣는다.
- 상품 이름·가격·원래 가격·마감일·지점처럼 홈페이지에 적힌 사실만 저장한다. 이미지나 설명 글은 가져오지 않는다.
- 병원이 빼 달라고 하면 `bin/collect.dart`의 `excludedBranches`에 넣는다 (이슈로 요청).
- 병원에서 광고비·수수료를 받거나 예약을 중개하지 않는다 (의료법 제27조 3항). 앱은 홈페이지 링크만 보여준다.
