/* مصروفي: فهم رسايل البنوك والمحافظ (خصم / إيداع / تحويل / سحب) */
(function (root) {
  'use strict';
  const P = root.MasroofyParser || (typeof require !== 'undefined' ? require('./parser.js') : null);
  const N = s => P.normalize(s);

  // الجهات المعروفه: اسم المرسل (أو ذكرها في الرساله) → نوع الحساب
  const PROVIDERS = [
    { id: 'vodafone', name: 'فودافون كاش', type: 'wallet', re: /(vf ?cash|vodafone ?cash|vodafone|فودافون ?كاش|^vf\b)/ },
    { id: 'orange', name: 'اورنج كاش', type: 'wallet', re: /(orange ?cash|orange ?money|orange|اورنج ?كاش|اورنج ?موني)/ },
    { id: 'etisalat', name: 'اتصالات كاش', type: 'wallet', re: /(etisalat ?cash|e& ?cash|اتصالات ?كاش|e& money|etisalat)/ },
    { id: 'wepay', name: 'وي باي', type: 'wallet', re: /(we ?pay|وي ?باي)/ },
    { id: 'telda', name: 'تيلدا', type: 'bank', re: /telda|تيلدا/ },
    { id: 'cib', name: 'CIB', type: 'bank', re: /\bcib\b|التجاري الدولي/ },
    { id: 'nbe', name: 'البنك الأهلي', type: 'bank', re: /\bnbe\b|ahly ?bank|البنك الاهلي|الاهلي المصري/ },
    { id: 'misr', name: 'بنك مصر', type: 'bank', re: /banque ?misr|bank ?misr|\bbm\b|بنك مصر/ },
    { id: 'qnb', name: 'QNB', type: 'bank', re: /\bqnb\b/ },
    { id: 'aaib', name: 'البنك العربي الأفريقي', type: 'bank', re: /\baaib\b/ },
    { id: 'hsbc', name: 'HSBC', type: 'bank', re: /\bhsbc\b/ },
    { id: 'alex', name: 'بنك الإسكندرية', type: 'bank', re: /alex ?bank|بنك الاسكندريه/ },
    { id: 'bdc', name: 'بنك القاهرة', type: 'bank', re: /banque du caire|\bbdc\b|بنك القاهره/ },
    { id: 'adib', name: 'مصرف أبوظبي الإسلامي', type: 'bank', re: /\badib\b/ },
    { id: 'faisal', name: 'بنك فيصل', type: 'bank', re: /faisal|فيصل/ },
    { id: 'enbd', name: 'الإمارات دبي الوطني', type: 'bank', re: /emirates ?nbd|\benbd\b/ },
    { id: 'saib', name: 'SAIB', type: 'bank', re: /\bsaib\b/ },
    { id: 'mashreq', name: 'المشرق', type: 'bank', re: /mashreq/ },
    { id: 'nbk', name: 'NBK', type: 'bank', re: /\bnbk\b/ },
    { id: 'aib', name: 'AIB', type: 'bank', re: /\baib\b/ },
    { id: 'abk', name: 'ABK', type: 'bank', re: /\babk\b/ },
    { id: 'halan', name: 'حالا', type: 'wallet', re: /halan|حالا/ },
    { id: 'valu', name: 'ڤاليو', type: 'other', re: /\bvalu\b|فاليو/ },
    { id: 'instapay', name: 'انستاباي', type: 'instapay', re: /instapay|insta pay|\bipn\b|انستا ?باي/ }
  ];

  const CUR = '(?:egp|le|l e|جم|ج م|جنيه|جنيها|جنيهات|جنية|ج)';
  const NUM = '(\\d{1,3}(?:,\\d{3})+(?:\\.\\d+)?|\\d+(?:\\.\\d+)?)';
  const num = s => parseFloat(String(s).replace(/,/g, ''));

  const OTP = /(otp|رمز التحقق|كود التحقق|رمز التفعيل|كود التفعيل|verification code|one time|كلمه المرور المؤقته|passcode|activation code|رقمك السري|الرقم السري)/;
  const ATM = /(atm|صراف|ماكينه|سحب نقدي|سحب نقدى|cash withdrawal)/;
  const REFUND = /(استرداد|refund|reversal|مرتجع|استرجاع)/;
  const DEBIT_HARD = /(خصم|debited|charged|purchase|شراء|مشتريات|spent|paid|payment|دفع|سداد|سحب|withdraw)/;
  const DEBIT_SOFT = /(sent|transferred to|transfer to|transfer of .{0,30} to |تحويل .{0,40}(الي|لرقم|لحساب|ل \d|ل\d)|تم ارسال|ارسال)/;
  const CREDIT = /(ايداع|اضافه|استلام|استلمت|وارد|وارده|credited|received|deposit|added to|الي حسابك|لحسابك|اليك|to your account|into your|تحويل لحظي من|حواله من|من رقم)/;
  const TRANSFER = /(تحويل|transfer|instapay|انستاباي|انستا باي|ipn|حواله|ارسال|sent|received|استلام)/;
  const BALANCE = new RegExp('(رصيد(?:ك|كم)?(?: الحالي| المتاح| الجديد| حسابك)?|(?:available |avl |avail |new |current )?bal(?:ance)?)\\s*(?:هو|is|:)?\\s*' + CUR + '?\\s*' + NUM);

  function providerFor(text) {
    const t = N(text);
    return PROVIDERS.find(p => p.re.test(t)) || null;
  }

  function isPhoneSender(addr) { return /^\+?\d[\d\s-]{6,}$/.test(String(addr || '').trim()); }

  function findAmount(t) {
    const cands = [];
    const re1 = new RegExp(CUR + '\\s*' + NUM, 'g');
    const re2 = new RegExp(NUM + '\\s*' + CUR + '(?=\\s|$|\\W)', 'g');
    const re3 = new RegExp('(?:مبلغ|بمبلغ|بقيمه|قيمه|amount(?: of)?|of)\\s*' + CUR + '?\\s*' + NUM, 'g');
    [re1, re2, re3].forEach(re => { let m; while ((m = re.exec(t))) cands.push({ v: num(m[1]), i: m.index, end: m.index + m[0].length }); });
    cands.sort((a, b) => a.i - b.i);
    for (const c of cands) {
      const before = t.slice(Math.max(0, c.i - 28), c.i);
      if (/(رصيد|balance|bal\b|avl|المتاح|limit|الحد)/.test(before)) continue;
      if (!(c.v > 0) || c.v > 1e8) continue;
      return c.v;
    }
    return null;
  }

  function merchantOf(orig) {
    const o = String(orig).replace(/[٠-٩]/g, d => '٠١٢٣٤٥٦٧٨٩'.indexOf(d));
    const pats = [
      /\b(?:at|@|merchant:?)\s+([A-Za-z0-9][A-Za-z0-9 &'._\-]{1,40}?)(?=\s+on\b|\s+in\b|\s+dated|\s+at\b|[,;]|\.\s|\.$|\s+\d{1,2}[\/-]|$)/i,
      /(?:^|[\s،,.])(?:لرقم|للرقم|to number|to mobile)\s*(\+?\d[\d\s]{7,14}\d)/i,
      /(?:^|[\s،,.])(?:من رقم|from number|from mobile|from)\s*(\+?\d[\d\s]{7,14}\d)/i,
      /(?:^|[\s،,.])(?:لدى|لدي|لدىّ|عند|من عند|في متجر|بمتجر|التاجر)\s+([^\s،,.]+(?:\s+[^\s،,.\d]+){0,3}?)(?=\s+(?:بتاريخ|يوم|في|الساعه|الساعة|رصيد|برقم)|[،,.]|$)/,
      /\b(?:to|for)\s+([A-Za-z][A-Za-z0-9 &'._\-]{1,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+from\b|\s+was\b|\s+is\b|\s+has\b|\s+successful|[,;]|\.\s|\.$|$)/i,
      /(?:^|[\s،,.])(?:الى|إلى|الي|إلي|لصالح|للمستفيد)\s+([^\s،,.]+(?:\s+[^\s،,.\d]+){0,3}?)(?=\s+(?:بنجاح|بتاريخ|يوم|رقم|برقم|عن طريق|من)|[،,.]|$)/,
      /\b(?:from)\s+([A-Za-z][A-Za-z0-9 &'._\-]{1,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+was\b|\s+has\b|[,;]|\.\s|\.$|$)/i,
      /(?:^|[\s،,.])(?:من)\s+((?!حساب|بطاق|رقم|كارت)[^\s،,.\d]+(?:\s+[^\s،,.\d]+){0,2}?)(?=\s+(?:بنجاح|بتاريخ|يوم|علي|على|عن طريق)|[،,.]|$)/,
    ];
    for (const re of pats) {
      const m = o.match(re);
      if (m && m[1]) {
        const s = m[1].trim().replace(/\s+/g, ' ');
        if (/^(your|ur|you|the|card|account|حساب|بطاق|EGP|LE)\b/i.test(s)) continue;
        if (providerFor(s)) continue; // اسم البنك أو المحفظه نفسها مش هو التاجر
        if (s.length >= 2) return s;
      }
    }
    return '';
  }

  /**
   * parse({address, body, date}) => null أو
   * { kind: 'expense'|'income'|'atm', amount, isTransfer, merchant, provider, balance, date, key }
   */
  function parse(msg) {
    const body = String(msg.body || '');
    const t = N(body);
    if (!t || OTP.test(t)) return null;
    const amount = findAmount(t);
    if (!amount) return null;
    const hasCur = new RegExp('(^|\\W|\\d)' + CUR + '(\\W|$|\\d)').test(t);
    const debitHard = DEBIT_HARD.test(t), debitSoft = DEBIT_SOFT.test(t), credit = CREDIT.test(t), refund = REFUND.test(t);
    let kind = null;
    if (ATM.test(t) && /(سحب|withdraw)/.test(t)) kind = 'atm';
    else if (refund) kind = 'income';
    else if (debitHard && !(credit && /(الي حسابك|لحسابك|اليك|to your account|into your|credited)/.test(t) && !/(خصم|debited|charged)/.test(t))) kind = 'expense';
    else if (credit) kind = 'income';
    else if (debitSoft) kind = 'expense';
    if (!kind || !hasCur) return null;
    let balance = null;
    const reB = new RegExp(BALANCE.source, 'g'); let bm;
    while ((bm = reB.exec(t))) { if (!/^0\d{9,}$/.test(bm[2])) { balance = num(bm[2]); break; } }
    const provider = (!isPhoneSender(msg.address) && providerFor(msg.address || '')) || providerFor(body);
    const date = msg.date ? new Date(+msg.date) : new Date();
    return {
      kind, amount,
      isTransfer: kind !== 'atm' && TRANSFER.test(t),
      merchant: merchantOf(body),
      provider,
      balance,
      date, time: date.getTime(),
      key: keyOf(msg)
    };
  }

  function keyOf(msg) {
    const s = N(msg.address || '') + '|' + N(msg.body || '').replace(/\s+/g, '');
    let h = 5381; for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
    return 'k' + (h >>> 0).toString(36) + s.length.toString(36);
  }

  // هل النص اللي اتلصق شكله رسالة بنك؟
  function looksLikeSms(text) {
    const t = N(text);
    if (t.length < 25) return false;
    return !!parse({ body: text }) && /(تم|your|you have|عزيزي|عميلنا|dear|حساب|account|card|بطاق|رصيد|balance|ref|مرجع)/.test(t);
  }

  const api = { parse, providerFor, isPhoneSender, looksLikeSms, keyOf, PROVIDERS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MasroofySms = api;
})(typeof window !== 'undefined' ? window : globalThis);
