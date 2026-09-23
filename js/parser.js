(() => {
  const actionRules = [
    [/アイドルステップ/i, '아이돌 스텝'],
    [/タジャドルポーズ/i, '타쟈도르 포즈'],
    [/直立/i, '직립'],
    [/立ち|立正面|立正|立$/i, '서기'],
    [/歩き|歩行/i, '걷기'],
    [/走り|疾走|ダッシュ/i, '달리기'],
    [/飛行|飛ぶ|フライ/i, '비행'],
    [/座り|座る|着席/i, '앉기'],
    [/寝|ぐでーん|横になる/i, '눕기'],
    [/太鼓/i, '북 연주'],
    [/祈願|お祈り/i, '기도'],
    [/指示|指さし/i, '지시'],
  ];
  const directionRules = [
    [/左向き|左向|左/i, '왼쪽'],
    [/右向き|右向|右/i, '오른쪽'],
    [/正面|前向き|前向/i, '정면'],
    [/後ろ|後向き|背面|後姿/i, '뒤'],
  ];
  const expressionRules = [
    [/(?:\^\^|＾＾)|にっこり|ニッコリ/i, '미소'],
    [/笑顔|えがお|スマイル/i, '웃음'],
    [/しょんぼり|ションボリ/i, '시무룩'],
    [/おこ|怒|ぷんぷん/i, '화남'],
    [/ジト目/i, '지토메'],
    [/目閉じ|目つぶり|閉眼/i, '눈 감음'],
    [/ぴわわ|ピワワ/i, '피와와'],
    [/＞＜|><|＞＜/i, '><'],
    [/ムッ|むっ/i, '뾰로통'],
    [/キリッ|きりっ/i, '키릿'],
    [/しっとり/i, '차분'],
    [/泣|涙/i, '울음'],
    [/照れ|赤面/i, '부끄러움'],
  ];
  const propRules = [
    [/はちみー|ハチミー/i, '하치미'],
    [/ペロキャン|ぺろキャン|ロリポップ/i, '막대사탕'],
    [/スイカ/i, '수박'],
    [/かき氷|カキ氷|氷菓/i, '빙수'],
    [/ラーメン/i, '라멘'],
    [/指示棒|指し棒/i, '지시봉'],
    [/ニンジン|人参|にんじん/i, '당근'],
    [/マイク/i, '마이크'],
    [/羽付き|羽|翼/i, '날개'],
    [/太鼓/i, '북'],
    [/旗|フラッグ/i, '깃발'],
    [/剣|サーベル|ソード/i, '검'],
    [/傘|アンブレラ/i, '우산'],
    [/帽子|ハット/i, '모자'],
    [/眼鏡|メガネ/i, '안경'],
  ];

  const knownNoise = /(gif|png|webp|jpg|jpeg)$/i;
  const numericLike = /^(?:\d{6,}|fu\d+|\d+(?:[-_]\d+)?)$/i;

  function stripExt(name) {
    return String(name || '').replace(/\.[^.]+$/, '');
  }
  function extOf(name) {
    const m = String(name || '').match(/\.([^.]+)$/);
    return m ? m[1].toLowerCase() : '';
  }
  function matchOne(text, rules, fallback='미지정') {
    for (const [re, label] of rules) if (re.test(text)) return label;
    return fallback;
  }
  function matchMany(text, rules) {
    const out=[];
    for (const [re,label] of rules) if (re.test(text) && !out.includes(label)) out.push(label);
    return out;
  }
  function humanizeCollection(raw) {
    if (!raw) return '기본';
    if (/不死鳥/.test(raw)) return '불사조 · 不死鳥';
    if (/改変素材/.test(raw)) return '개변 소재 · 改変素材';
    if (/雑穀/.test(raw)) return '잡곡 시리즈 · 雑穀';
    if (/うまり/.test(raw)) return '우마리 소재 · うまり';
    return raw;
  }
  function parseFilename(filename, collectionHint='') {
    const stem = stripExt(filename);
    const format = extOf(filename);
    const action = matchOne(stem, actionRules);
    const direction = matchOne(stem, directionRules);
    const expressions = matchMany(stem, expressionRules);
    const props = matchMany(stem, propRules);
    let collection = humanizeCollection(collectionHint);
    if ((!collectionHint || collection === '기본') && /不死鳥/.test(stem)) collection = '불사조 · 不死鳥';

    const meaningful = action !== '미지정' || direction !== '미지정' || expressions.length || props.length || collection !== '기본';
    const cleaned = stem.replace(/[\s._()\[\]【】・·_-]/g, '');
    const reviewRequired = numericLike.test(cleaned) || (!meaningful && /^\d/.test(cleaned));

    const tags = [];
    for (const v of [collection, action, direction, ...expressions, ...props]) {
      if (v && v !== '기본' && v !== '미지정' && !tags.includes(v)) tags.push(v);
    }
    return {
      title: stem,
      format: knownNoise.test(format) ? format : format,
      collection,
      action,
      direction,
      expressions,
      props,
      tags,
      reviewStatus: reviewRequired ? 'needs-review' : (meaningful ? 'auto' : 'unclassified'),
      reviewRequired
    };
  }
  function normalizeSearch(value) {
    return String(value || '')
      .normalize('NFKC')
      .toLowerCase()
      .replace(/[\s・·._()\[\]【】\-_/]/g, '');
  }
  window.TANUKI_PARSER = { parseFilename, normalizeSearch, humanizeCollection, stripExt, extOf };
})();
