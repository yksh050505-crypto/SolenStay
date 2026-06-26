// 숙박일지(.hwpx) 빌더 — 순수 Dart로 유효한 HWPX(OWPML/ZIP) 바이트를 생성한다.
//
// 구조 근거(실제로 한글에서 열리는 파일을 unzip해 확인):
//   - python-hwpx 테스트 코퍼스의 빈 문서  tool__blank.hwpx
//   - 한컴이 생성한 표 문서        reader_writer__SimpleTable.hwpx
//     (https://github.com/airmang/python-hwpx  tests/fixtures/hwpxlib_corpus/)
//   - 포맷 개요: https://tech.hancom.com/hwpxformat/
//
// 핵심 포인트:
//   - ZIP 첫 엔트리는 `mimetype`(application/hwp+zip)을 **무압축(STORED)** 으로.
//   - 필수: mimetype, version.xml, settings.xml, Contents/content.hpf,
//     Contents/header.xml, Contents/section0.xml,
//     META-INF/container.xml, META-INF/manifest.xml.
//   - header.xml refList(fontfaces/borderFills/charPr/paraPr/styles)의 id ↔
//     section0.xml의 *IDRef 참조 관계를 일치시킨다.
//   - 표: hp:tbl > hp:tr > hp:tc > hp:subList(+hp:p/hp:run/hp:t) +
//        hp:cellAddr/hp:cellSpan/hp:cellSz/hp:cellMargin.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 표의 한 행. 수령요금(fee)은 보통 빈 문자열 → 빈칸 출력.
class StayLogRow {
  final int seq;
  final DateTime date;
  final String name;
  final int nights;
  final String fee;
  const StayLogRow({
    required this.seq,
    required this.date,
    required this.name,
    required this.nights,
    this.fee = '',
  });
}

/// heading 문단 + 그 아래 표 1개.
class StayLogTable {
  final String heading;
  final List<StayLogRow> rows;
  const StayLogTable(this.heading, this.rows);
}

/// 숙박일지 HWPX 바이트(Uint8List)를 생성한다.
///
/// 문서 = title 큰 글씨 문단 + (각 table마다) heading 문단 + 표.
/// 표 컬럼: 연번 | 날짜 | 성명 | 숙박일수 | 수령요금.
Uint8List buildStayLogHwpx({
  required String title,
  required List<StayLogTable> tables,
}) {
  final mimeBytes = ascii.encode(_mimetype);

  final archive = Archive();
  // mimetype 은 반드시 첫 엔트리 + 무압축(STORED).
  archive.addFile(ArchiveFile('mimetype', mimeBytes.length, mimeBytes)..compress = false);
  _add(archive, 'version.xml', _versionXml);
  _add(archive, 'settings.xml', _settingsXml);
  _add(archive, 'Contents/content.hpf', _contentHpf);
  _add(archive, 'Contents/header.xml', _headerXml);
  _add(archive, 'Contents/section0.xml', _sectionXml(title: title, tables: tables));
  _add(archive, 'META-INF/container.xml', _containerXml);
  _add(archive, 'META-INF/manifest.xml', _manifestXml);

  final zip = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(zip);
}

void _add(Archive archive, String name, String xml) {
  final bytes = utf8.encode(xml);
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

// ───────────────────────── 고정 리소스 파일들 ─────────────────────────

const String _mimetype = 'application/hwp+zip';

/// 모든 OWPML 문서가 공유하는 네임스페이스 선언 묶음.
const String _ns =
    'xmlns:ha="http://www.hancom.co.kr/hwpml/2011/app" '
    'xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" '
    'xmlns:hp10="http://www.hancom.co.kr/hwpml/2016/paragraph" '
    'xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" '
    'xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core" '
    'xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" '
    'xmlns:hhs="http://www.hancom.co.kr/hwpml/2011/history" '
    'xmlns:hm="http://www.hancom.co.kr/hwpml/2011/master-page" '
    'xmlns:hpf="http://www.hancom.co.kr/schema/2011/hpf" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:opf="http://www.idpf.org/2007/opf/" '
    'xmlns:ooxmlchart="http://www.hancom.co.kr/hwpml/2016/ooxmlchart" '
    'xmlns:hwpunitchar="http://www.hancom.co.kr/hwpml/2016/HwpUnitChar" '
    'xmlns:epub="http://www.idpf.org/2007/ops" '
    'xmlns:config="urn:oasis:names:tc:opendocument:xmlns:config:1.0"';

const String _xmlDecl = '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>';

const String _versionXml =
    '$_xmlDecl<hv:HCFVersion xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version" '
    'tagetApplication="WORDPROCESSOR" major="5" minor="0" micro="5" buildNumber="0" '
    'xmlVersion="1.4" application="SolenStay" appVersion="1.0"/>';

const String _settingsXml =
    '$_xmlDecl<ha:HWPApplicationSetting '
    'xmlns:ha="http://www.hancom.co.kr/hwpml/2011/app" '
    'xmlns:config="urn:oasis:names:tc:opendocument:xmlns:config:1.0">'
    '<ha:CaretPosition listIDRef="0" paraIDRef="0" pos="0"/>'
    '</ha:HWPApplicationSetting>';

const String _containerXml =
    '$_xmlDecl<ocf:container '
    'xmlns:ocf="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:hpf="http://www.hancom.co.kr/schema/2011/hpf">'
    '<ocf:rootfiles>'
    '<ocf:rootfile full-path="Contents/content.hpf" media-type="application/hwpml-package+xml"/>'
    '</ocf:rootfiles></ocf:container>';

const String _manifestXml =
    '$_xmlDecl<odf:manifest '
    'xmlns:odf="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"/>';

const String _contentHpf =
    '$_xmlDecl<opf:package $_ns version="" unique-identifier="" id="">'
    '<opf:metadata>'
    '<opf:title/><opf:language>ko</opf:language>'
    '<opf:meta name="creator" content="SolenStay"/>'
    '</opf:metadata>'
    '<opf:manifest>'
    '<opf:item id="header" href="Contents/header.xml" media-type="application/xml"/>'
    '<opf:item id="section0" href="Contents/section0.xml" media-type="application/xml"/>'
    '<opf:item id="settings" href="settings.xml" media-type="application/xml"/>'
    '</opf:manifest>'
    '<opf:spine>'
    '<opf:itemref idref="header"/><opf:itemref idref="section0"/>'
    '</opf:spine></opf:package>';

// header.xml — refList 정의.
//   borderFill: 1=무테(페이지), 2=무테+빈채움(문단 기본), 3=실선 테두리(표 본문칸),
//               4=실선+회색 채움(표 머리행).
//   charPr: 0=본문(10pt), 1=제목(18pt,굵게), 2=구역제목(13pt,굵게), 3=표머리(굵게).
//   paraPr: 0=왼쪽(기본 본문/제목/구역제목), 1=가운데(표 칸).
final String _headerXml =
    '$_xmlDecl<hh:head $_ns version="1.4" secCnt="1">'
    '<hh:beginNum page="1" footnote="1" endnote="1" pic="1" tbl="1" equation="1"/>'
    '<hh:refList>'
    // ── fontfaces ──
    '<hh:fontfaces itemCnt="7">'
    '${_fontfaceLangs()}'
    '</hh:fontfaces>'
    // ── borderFills ──
    '<hh:borderFills itemCnt="4">'
    // 1: 전부 NONE (페이지 테두리용)
    '<hh:borderFill id="1" threeD="0" shadow="0" centerLine="NONE" breakCellSeparateLine="0">'
    '<hh:slash type="NONE" Crooked="0" isCounter="0"/><hh:backSlash type="NONE" Crooked="0" isCounter="0"/>'
    '<hh:leftBorder type="NONE" width="0.1 mm" color="#000000"/><hh:rightBorder type="NONE" width="0.1 mm" color="#000000"/>'
    '<hh:topBorder type="NONE" width="0.1 mm" color="#000000"/><hh:bottomBorder type="NONE" width="0.1 mm" color="#000000"/>'
    '<hh:diagonal type="SOLID" width="0.1 mm" color="#000000"/></hh:borderFill>'
    // 2: NONE + 투명 채움 (문단 기본 charPr 참조용)
    '<hh:borderFill id="2" threeD="0" shadow="0" centerLine="NONE" breakCellSeparateLine="0">'
    '<hh:slash type="NONE" Crooked="0" isCounter="0"/><hh:backSlash type="NONE" Crooked="0" isCounter="0"/>'
    '<hh:leftBorder type="NONE" width="0.1 mm" color="#000000"/><hh:rightBorder type="NONE" width="0.1 mm" color="#000000"/>'
    '<hh:topBorder type="NONE" width="0.1 mm" color="#000000"/><hh:bottomBorder type="NONE" width="0.1 mm" color="#000000"/>'
    '<hh:diagonal type="SOLID" width="0.1 mm" color="#000000"/>'
    '<hc:fillBrush><hc:winBrush faceColor="none" hatchColor="#FF000000" alpha="0"/></hc:fillBrush></hh:borderFill>'
    // 3: 실선 사방 테두리 (표 본문칸)
    '<hh:borderFill id="3" threeD="0" shadow="0" centerLine="NONE" breakCellSeparateLine="0">'
    '<hh:slash type="NONE" Crooked="0" isCounter="0"/><hh:backSlash type="NONE" Crooked="0" isCounter="0"/>'
    '<hh:leftBorder type="SOLID" width="0.12 mm" color="#000000"/><hh:rightBorder type="SOLID" width="0.12 mm" color="#000000"/>'
    '<hh:topBorder type="SOLID" width="0.12 mm" color="#000000"/><hh:bottomBorder type="SOLID" width="0.12 mm" color="#000000"/>'
    '<hh:diagonal type="SOLID" width="0.1 mm" color="#000000"/></hh:borderFill>'
    // 4: 실선 테두리 + 회색 채움 (표 머리행)
    '<hh:borderFill id="4" threeD="0" shadow="0" centerLine="NONE" breakCellSeparateLine="0">'
    '<hh:slash type="NONE" Crooked="0" isCounter="0"/><hh:backSlash type="NONE" Crooked="0" isCounter="0"/>'
    '<hh:leftBorder type="SOLID" width="0.12 mm" color="#000000"/><hh:rightBorder type="SOLID" width="0.12 mm" color="#000000"/>'
    '<hh:topBorder type="SOLID" width="0.12 mm" color="#000000"/><hh:bottomBorder type="SOLID" width="0.12 mm" color="#000000"/>'
    '<hh:diagonal type="SOLID" width="0.1 mm" color="#000000"/>'
    '<hc:fillBrush><hc:winBrush faceColor="#D9D9D9" hatchColor="#000000" alpha="0"/></hc:fillBrush></hh:borderFill>'
    '</hh:borderFills>'
    // ── charProperties ──
    '<hh:charProperties itemCnt="4">'
    '${_charPr(0, height: 1000, bold: false)}' // 본문 10pt
    '${_charPr(1, height: 1800, bold: true)}'  // 제목 18pt 굵게
    '${_charPr(2, height: 1300, bold: true)}'  // 구역제목 13pt 굵게
    '${_charPr(3, height: 1000, bold: true)}'  // 표 머리 10pt 굵게
    '</hh:charProperties>'
    // ── tabProperties ──
    '<hh:tabProperties itemCnt="1"><hh:tabPr id="0" autoTabLeft="0" autoTabRight="0"/></hh:tabProperties>'
    // ── numberings ──
    '<hh:numberings itemCnt="1"><hh:numbering id="1" start="0">'
    '<hh:paraHead start="1" level="1" align="LEFT" useInstWidth="1" autoIndent="1" widthAdjust="0" '
    'textOffsetType="PERCENT" textOffset="50" numFormat="DIGIT" charPrIDRef="4294967295" checkable="0">^1.</hh:paraHead>'
    '</hh:numbering></hh:numberings>'
    // ── paraProperties ──
    '<hh:paraProperties itemCnt="2">'
    '${_paraPr(0, align: 'LEFT')}'   // 일반 왼쪽 정렬
    '${_paraPr(1, align: 'CENTER')}' // 표 칸 가운데 정렬
    '</hh:paraProperties>'
    // ── styles ──
    '<hh:styles itemCnt="1">'
    '<hh:style id="0" type="PARA" name="바탕글" engName="Normal" paraPrIDRef="0" charPrIDRef="0" '
    'nextStyleIDRef="0" langID="1042" lockForm="0"/>'
    '</hh:styles>'
    '</hh:refList>'
    '<hh:compatibleDocument targetProgram="HWP201X"><hh:layoutCompatibility/></hh:compatibleDocument>'
    '<hh:docOption><hh:linkinfo path="" pageInherit="0" footnoteInherit="0"/></hh:docOption>'
    '</hh:head>';

/// 7개 언어 영역 모두 동일 폰트(함초롬돋움/바탕)로 채운 fontface 묶음.
String _fontfaceLangs() {
  const langs = ['HANGUL', 'LATIN', 'HANJA', 'JAPANESE', 'OTHER', 'SYMBOL', 'USER'];
  final b = StringBuffer();
  for (final lang in langs) {
    b.write('<hh:fontface lang="$lang" fontCnt="2">'
        '<hh:font id="0" face="함초롬돋움" type="TTF" isEmbedded="0">'
        '<hh:typeInfo familyType="FCAT_GOTHIC" weight="8" proportion="4" contrast="0" '
        'strokeVariation="1" armStyle="1" letterform="1" midline="1" xHeight="1"/></hh:font>'
        '<hh:font id="1" face="함초롬바탕" type="TTF" isEmbedded="0">'
        '<hh:typeInfo familyType="FCAT_GOTHIC" weight="8" proportion="4" contrast="0" '
        'strokeVariation="1" armStyle="1" letterform="1" midline="1" xHeight="1"/></hh:font>'
        '</hh:fontface>');
  }
  return b.toString();
}

/// charPr 한 개. height 단위는 1/100 pt (1000 = 10pt).
String _charPr(int id, {required int height, required bool bold}) {
  final boldTag = bold ? '<hh:bold/>' : '';
  return '<hh:charPr id="$id" height="$height" textColor="#000000" shadeColor="none" '
      'useFontSpace="0" useKerning="0" symMark="NONE" borderFillIDRef="2">'
      '<hh:fontRef hangul="0" latin="0" hanja="0" japanese="0" other="0" symbol="0" user="0"/>'
      '<hh:ratio hangul="100" latin="100" hanja="100" japanese="100" other="100" symbol="100" user="100"/>'
      '<hh:spacing hangul="0" latin="0" hanja="0" japanese="0" other="0" symbol="0" user="0"/>'
      '<hh:relSz hangul="100" latin="100" hanja="100" japanese="100" other="100" symbol="100" user="100"/>'
      '<hh:offset hangul="0" latin="0" hanja="0" japanese="0" other="0" symbol="0" user="0"/>'
      '$boldTag'
      '<hh:underline type="NONE" shape="SOLID" color="#000000"/>'
      '<hh:strikeout shape="NONE" color="#000000"/>'
      '<hh:outline type="NONE"/>'
      '<hh:shadow type="NONE" color="#B2B2B2" offsetX="10" offsetY="10"/>'
      '</hh:charPr>';
}

/// paraPr 한 개. align: LEFT / CENTER / JUSTIFY 등.
String _paraPr(int id, {required String align}) {
  return '<hh:paraPr id="$id" tabPrIDRef="0" condense="0" fontLineHeight="0" '
      'snapToGrid="1" suppressLineNumbers="0" checked="0">'
      '<hh:align horizontal="$align" vertical="BASELINE"/>'
      '<hh:heading type="NONE" idRef="0" level="0"/>'
      '<hh:breakSetting breakLatinWord="KEEP_WORD" breakNonLatinWord="BREAK_WORD" '
      'widowOrphan="0" keepWithNext="0" keepLines="0" pageBreakBefore="0" lineWrap="BREAK"/>'
      '<hh:margin>'
      '<hc:intent value="0" unit="HWPUNIT"/><hc:left value="0" unit="HWPUNIT"/>'
      '<hc:right value="0" unit="HWPUNIT"/><hc:prev value="0" unit="HWPUNIT"/>'
      '<hc:next value="0" unit="HWPUNIT"/></hh:margin>'
      '<hh:lineSpacing type="PERCENT" value="160" unit="HWPUNIT"/>'
      '<hh:autoSpacing eAsianEng="0" eAsianNum="0"/>'
      '<hh:border borderFillIDRef="2" offsetLeft="0" offsetRight="0" offsetTop="0" '
      'offsetBottom="0" connect="0" ignoreMargin="0"/></hh:paraPr>';
}

// ───────────────────────── section0.xml (본문) ─────────────────────────

// A4 세로. 본문 텍스트폭(좌우 여백 제외) ≈ 50,360 HWPUNIT.
const int _pageWidth = 59528;
const int _pageHeight = 84188;
const int _marginLeft = 8504;
const int _marginRight = 8504;
const int _textWidth = _pageWidth - _marginLeft - _marginRight; // 42520

// 표 컬럼 폭(HWPUNIT) — 합계가 _textWidth(42520)에 맞도록.
//   연번 | 날짜 | 성명 | 숙박일수 | 수령요금
const List<int> _colWidths = [4520, 11000, 10000, 8000, 9000];
const List<String> _headers = ['연번', '날짜', '성명', '숙박일수', '수령요금'];

const int _rowHeight = 2886; // 한 행 높이(HWPUNIT). 한글이 열 때 재계산함.

String _sectionXml({required String title, required List<StayLogTable> tables}) {
  final body = StringBuffer();

  // 첫 문단: secPr/ctrl 를 담은 run + 제목 텍스트.
  body.write('<hp:p id="0" paraPrIDRef="0" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">');
  body.write('<hp:run charPrIDRef="1">'); // 제목 charPr
  body.write(_secPr());
  body.write('<hp:ctrl><hp:colPr id="" type="NEWSPAPER" layout="LEFT" colCount="1" sameSz="1" sameGap="0"/></hp:ctrl>');
  body.write('<hp:t>${_esc(title)}</hp:t>');
  body.write('</hp:run></hp:p>');

  // 빈 줄 한 개.
  body.write(_emptyPara());

  for (final t in tables) {
    // 구역 제목 문단.
    body.write('<hp:p id="0" paraPrIDRef="0" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">');
    body.write('<hp:run charPrIDRef="2"><hp:t>${_esc(t.heading)}</hp:t></hp:run>');
    body.write('</hp:p>');

    // 표를 담는 문단 (표는 run 안에 위치, 뒤에 빈 hp:t).
    body.write('<hp:p id="0" paraPrIDRef="0" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">');
    body.write('<hp:run charPrIDRef="0">');
    body.write(_tableXml(t.rows));
    body.write('<hp:t/></hp:run></hp:p>');

    // 표 사이 빈 줄.
    body.write(_emptyPara());
  }

  return '$_xmlDecl<hs:sec $_ns>${body.toString()}</hs:sec>';
}

String _emptyPara() =>
    '<hp:p id="0" paraPrIDRef="0" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">'
    '<hp:run charPrIDRef="0"><hp:t/></hp:run></hp:p>';

String _secPr() {
  return '<hp:secPr id="" textDirection="HORIZONTAL" spaceColumns="1134" tabStop="8000" '
      'tabStopVal="4000" tabStopUnit="HWPUNIT" outlineShapeIDRef="1" memoShapeIDRef="0" '
      'textVerticalWidthHead="0" masterPageCnt="0">'
      '<hp:grid lineGrid="0" charGrid="0" wonggojiFormat="0"/>'
      '<hp:startNum pageStartsOn="BOTH" page="0" pic="0" tbl="0" equation="0"/>'
      '<hp:visibility hideFirstHeader="0" hideFirstFooter="0" hideFirstMasterPage="0" '
      'border="SHOW_ALL" fill="SHOW_ALL" hideFirstPageNum="0" hideFirstEmptyLine="0" showLineNumber="0"/>'
      '<hp:lineNumberShape restartType="0" countBy="0" distance="0" startNumber="0"/>'
      '<hp:pagePr landscape="WIDELY" width="$_pageWidth" height="$_pageHeight" gutterType="LEFT_ONLY">'
      '<hp:margin header="4252" footer="4252" gutter="0" left="$_marginLeft" right="$_marginRight" '
      'top="5668" bottom="4252"/></hp:pagePr>'
      '<hp:footNotePr>'
      '<hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/>'
      '<hp:noteLine length="-1" type="SOLID" width="0.12 mm" color="#000000"/>'
      '<hp:noteSpacing betweenNotes="283" belowLine="567" aboveLine="850"/>'
      '<hp:numbering type="CONTINUOUS" newNum="1"/>'
      '<hp:placement place="EACH_COLUMN" beneathText="0"/></hp:footNotePr>'
      '<hp:endNotePr>'
      '<hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/>'
      '<hp:noteLine length="14692344" type="SOLID" width="0.12 mm" color="#000000"/>'
      '<hp:noteSpacing betweenNotes="0" belowLine="567" aboveLine="850"/>'
      '<hp:numbering type="CONTINUOUS" newNum="1"/>'
      '<hp:placement place="END_OF_DOCUMENT" beneathText="0"/></hp:endNotePr>'
      '<hp:pageBorderFill type="BOTH" borderFillIDRef="1" textBorder="PAPER" headerInside="0" '
      'footerInside="0" fillArea="PAPER"><hp:offset left="1417" right="1417" top="1417" bottom="1417"/></hp:pageBorderFill>'
      '<hp:pageBorderFill type="EVEN" borderFillIDRef="1" textBorder="PAPER" headerInside="0" '
      'footerInside="0" fillArea="PAPER"><hp:offset left="1417" right="1417" top="1417" bottom="1417"/></hp:pageBorderFill>'
      '<hp:pageBorderFill type="ODD" borderFillIDRef="1" textBorder="PAPER" headerInside="0" '
      'footerInside="0" fillArea="PAPER"><hp:offset left="1417" right="1417" top="1417" bottom="1417"/></hp:pageBorderFill>'
      '</hp:secPr>';
}

String _tableXml(List<StayLogRow> rows) {
  final rowCnt = rows.length + 1; // 머리행 포함
  final colCnt = _headers.length;
  final tableWidth = _colWidths.fold<int>(0, (a, b) => a + b);
  // 컬럼 폭 합계는 본문 텍스트폭과 일치(표가 페이지 폭에 꽉 차도록).
  assert(tableWidth == _textWidth);
  final tableHeight = _rowHeight * rowCnt;

  final b = StringBuffer();
  b.write('<hp:tbl id="0" zOrder="0" numberingType="TABLE" textWrap="TOP_AND_BOTTOM" '
      'textFlow="BOTH_SIDES" lock="0" dropcapstyle="None" pageBreak="CELL" repeatHeader="1" '
      'rowCnt="$rowCnt" colCnt="$colCnt" cellSpacing="0" borderFillIDRef="3" noAdjust="0">');
  b.write('<hp:sz width="$tableWidth" widthRelTo="ABSOLUTE" height="$tableHeight" '
      'heightRelTo="ABSOLUTE" protect="0"/>');
  b.write('<hp:pos treatAsChar="0" affectLSpacing="0" flowWithText="1" allowOverlap="0" '
      'holdAnchorAndSO="0" vertRelTo="PARA" horzRelTo="COLUMN" vertAlign="TOP" horzAlign="LEFT" '
      'vertOffset="0" horzOffset="0"/>');
  b.write('<hp:outMargin left="283" right="283" top="283" bottom="283"/>');
  b.write('<hp:inMargin left="510" right="510" top="141" bottom="141"/>');

  // 머리행 (borderFill 4 = 음영, charPr 3 = 굵게).
  b.write('<hp:tr>');
  for (var c = 0; c < colCnt; c++) {
    b.write(_cellXml(
      text: _headers[c],
      colAddr: c,
      rowAddr: 0,
      width: _colWidths[c],
      borderFillId: 4,
      charPrId: 3,
    ));
  }
  b.write('</hp:tr>');

  // 데이터 행.
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final values = [
      '${row.seq}',
      _fmtDate(row.date),
      row.name,
      '${row.nights}박',
      row.fee,
    ];
    b.write('<hp:tr>');
    for (var c = 0; c < colCnt; c++) {
      b.write(_cellXml(
        text: values[c],
        colAddr: c,
        rowAddr: r + 1,
        width: _colWidths[c],
        borderFillId: 3,
        charPrId: 0,
      ));
    }
    b.write('</hp:tr>');
  }

  b.write('</hp:tbl>');
  return b.toString();
}

String _cellXml({
  required String text,
  required int colAddr,
  required int rowAddr,
  required int width,
  required int borderFillId,
  required int charPrId,
}) {
  final t = text.isEmpty ? '<hp:t/>' : '<hp:t>${_esc(text)}</hp:t>';
  return '<hp:tc name="" header="${rowAddr == 0 ? 1 : 0}" hasMargin="0" protect="0" '
      'editable="0" dirty="0" borderFillIDRef="$borderFillId">'
      '<hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="CENTER" '
      'linkListIDRef="0" linkListNextIDRef="0" textWidth="0" textHeight="0" hasTextRef="0" hasNumRef="0">'
      '<hp:p id="0" paraPrIDRef="1" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">'
      '<hp:run charPrIDRef="$charPrId">$t</hp:run></hp:p>'
      '</hp:subList>'
      '<hp:cellAddr colAddr="$colAddr" rowAddr="$rowAddr"/>'
      '<hp:cellSpan colSpan="1" rowSpan="1"/>'
      '<hp:cellSz width="$width" height="$_rowHeight"/>'
      '<hp:cellMargin left="510" right="510" top="141" bottom="141"/>'
      '</hp:tc>';
}

String _fmtDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// XML 텍스트 escape (& < > " ').
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
