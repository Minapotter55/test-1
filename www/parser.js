/* مصروفي: تحويل الكلام (عامية مصرية) لعمليات مالية منظمة */
(function (root) {
  'use strict';

  function normalize(s) {
    return String(s || '')
      .toLowerCase()
      .replace(/[ً-ْـ]/g, '') // تشكيل وتطويل
      .replace(/[٠-٩]/g, d => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
      .replace(/[۰-۹]/g, d => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)))
      .replace(/٫/g, '.').replace(/٬/g, ',')
      .replace(/[أإآٱ]/g, 'ا')
      .replace(/ة/g, 'ه')
      .replace(/ى/g, 'ي')
      .replace(/ؤ/g, 'و').replace(/ئ/g, 'ي')
      .replace(/(\d)\.(?=\d)/g, '$1\u0001')
      .replace(/[؟?!.:"'()«»]/g, ' ')
      .replace(/\u0001/g, '.')
      .replace(/\s+/g, ' ')
      .trim();
  }

  const W = {};
  const add = (v, ...words) => words.forEach(w => { W[normalize(w)] = v; });
  add(1, 'واحد', 'واحده');
  add(2, 'اتنين', 'اثنين', 'اثنان');
  add(3, 'تلاته', 'ثلاثه', 'تلات', 'ثلاث');
  add(4, 'اربعه', 'اربع');
  add(5, 'خمسه', 'خمس');
  add(6, 'سته', 'ست');
  add(7, 'سبعه', 'سبع');
  add(8, 'تمانيه', 'ثمانيه', 'تمن', 'ثمان', 'تماني');
  add(9, 'تسعه', 'تسع');
  add(10, 'عشره', 'عشر');
  add(11, 'حداشر', 'احداشر', 'احدعشر');
  add(12, 'اتناشر', 'اثناشر');
  add(13, 'تلتاشر', 'ثلتاشر');
  add(14, 'اربعتاشر', 'اربعطاشر');
  add(15, 'خمستاشر', 'خمسطاشر');
  add(16, 'ستاشر', 'سطاشر');
  add(17, 'سبعتاشر', 'سبعطاشر');
  add(18, 'تمنتاشر', 'تمنطاشر');
  add(19, 'تسعتاشر', 'تسعطاشر');
  add(20, 'عشرين', 'عشرون');
  add(30, 'تلاتين', 'ثلاثين');
  add(40, 'اربعين');
  add(50, 'خمسين');
  add(60, 'ستين');
  add(70, 'سبعين');
  add(80, 'تمانين', 'ثمانين');
  add(90, 'تسعين');
  add(100, 'ميه', 'مايه', 'مائه', 'ميت', 'مية');
  add(200, 'ميتين', 'مائتين', 'مايتين');
  add(300, 'تلتميه', 'ثلاثمائه', 'تلاتميه', 'ثلثميه');
  add(400, 'ربعميه', 'اربعمائه', 'اربعميه');
  add(500, 'خمسميه', 'خمسمائه');
  add(600, 'ستميه', 'ستمائه');
  add(700, 'سبعميه', 'سبعمائه');
  add(800, 'تمنميه', 'ثمانمائه', 'تمانميه');
  add(900, 'تسعميه', 'تسعمائه');
  add(2000, 'الفين', 'الفان');
  const MULT = {};
  ['الف', 'الاف', 'تلاف', 'ترلاف', 'k'].forEach(w => { MULT[normalize(w)] = 1000; });
  ['مليون', 'ملايين'].forEach(w => { MULT[normalize(w)] = 1e6; });
  const FRAC = { [normalize('نص')]: 0.5, [normalize('نصف')]: 0.5, [normalize('ربع')]: 0.25 };

  function tokenValue(tok) {
    if (/^\d+(?:[.,]\d+)*$/.test(tok)) {
      // 1,500 أو 1.5
      const t = /^\d{1,3}(,\d{3})+$/.test(tok) ? tok.replace(/,/g, '') : tok.replace(',', '.');
      return { kind: 'num', v: parseFloat(t) };
    }
    if (W[tok] !== undefined) return { kind: 'num', v: W[tok] };
    if (MULT[tok] !== undefined) return { kind: 'mult', v: MULT[tok] };
    if (FRAC[tok] !== undefined) return { kind: 'frac', v: FRAC[tok] };
    return null;
  }

  function classify(tok) {
    const direct = tokenValue(tok);
    if (direct) return direct;
    for (const pre of ['و', 'ب', 'وب']) {
      if (tok.length > pre.length + 1 && tok.startsWith(pre)) {
        const inner = tokenValue(tok.slice(pre.length));
        if (inner) return inner;
      }
    }
    return null;
  }

  // يحوّل الأرقام المكتوبة بالكلام لأرقام: "الف وميتين وخمسين" -> "1250"
  function wordsToNumbers(text) {
    const toks = text.split(' ');
    const out = [];
    let i = 0;
    while (i < toks.length) {
      const c = classify(toks[i]);
      if (!c || c.kind === 'frac') { out.push(toks[i]); i++; continue; }
      let total = 0, cur = 0, lastMult = 1, j = i, lastWasNum = false;
      const lead = toks[i].length > 1 && toks[i][0] === 'و' && !tokenValue(toks[i]) ? 'و' : '';
      while (j < toks.length) {
        let t = toks[j];
        if (t === 'و') { // واو منفصله بين رقمين
          const nx = j + 1 < toks.length ? classify(toks[j + 1]) : null;
          if (nx) { j++; continue; }
          break;
        }
        const k = classify(t);
        if (!k) break;
        if (k.kind === 'num') {
          if (lastWasNum && cur !== 0 && k.v >= cur && !(t[0] === 'و')) break; // "50 100" رقمين منفصلين
          cur += k.v; lastWasNum = true;
        } else if (k.kind === 'mult') {
          cur = (cur || 1) * k.v; total += cur; cur = 0; lastMult = k.v; lastWasNum = false;
        } else if (k.kind === 'frac') {
          if (lastMult > 1 && cur === 0) { total += k.v * lastMult; j++; }
          break;
        }
        j++;
      }
      const val = total + cur;
      if (j === i) { out.push(toks[i]); i++; continue; }
      out.push(lead + String(Math.round(val * 100) / 100));
      i = j;
    }
    return out.join(' ');
  }

  const CURRENCY = /(^|\s)(جنيه|جنيهات|جنية|جنيهات|ج|جم|ج م|ليره|ليرات|بوند|egp|le|pounds?)(?=\s|$)/g;
  const INCOME = ['قبضت', 'قبض', 'مرتب', 'المرتب', 'استلمت', 'جالي', 'جاتلي', 'جالى', 'دخلي', 'دخل لي', 'كسبت', 'اتحولي', 'حولولي', 'حولي', 'بعتولي', 'بعتلي', 'مكافاه', 'عيديه', 'اخدت فلوس', 'رجعلي', 'رجعولي'].map(normalize);
  const TRANSFER = ['سحبت', 'حولت', 'نقلت', 'شحنت', 'حطيت', 'ايداع', 'اودعت'].map(normalize);
  const FILLER = ['دفعت', 'دفعنا', 'صرفت', 'اشتريت', 'اشترينا', 'جبت', 'جبنا', 'خدت', 'اخدت', 'دفع', 'النهارده', 'انهارده', 'امبارح', 'اول', 'امس', 'حق', 'ب', 'علي', 'في', 'عشان', 'من', 'تمن', 'ثمن', 'انا', 'كده', 'حوالي', 'بتاع', 'بتاعه', 'بتاعت', 'على'].map(normalize);

  function findAccounts(seg, accounts) {
    const hits = [];
    const list = [];
    accounts.forEach(a => {
      const kws = [a.name].concat(a.keywords || []).map(normalize).filter(Boolean);
      kws.forEach(k => list.push({ k, a }));
    });
    list.sort((x, y) => y.k.length - x.k.length);
    let masked = ' ' + seg + ' ';
    list.forEach(({ k, a }) => {
      let idx = masked.indexOf(k);
      while (idx !== -1) {
        const before = masked[idx - 1], after = masked[idx + k.length];
        const okB = before === ' ' || before === 'ب' || before === 'ل' || before === 'و' || (before === 'ل' ) || masked.slice(idx - 2, idx) === 'ال';
        const okA = after === ' ' || after === undefined || after === 'ي';
        if (okB && okA) {
          const pre = masked.slice(Math.max(0, idx - 6), idx);
          hits.push({ account: a, pos: idx, from: /(^|\s)من\s*(ال)?$/.test(pre), to: /(^|\s)(ل|لل|علي|الي|في)\s*(ال)?$|(^|\s)(ل|لل)$/.test(pre) });
          masked = masked.slice(0, idx) + ' '.repeat(k.length) + masked.slice(idx + k.length);
        }
        idx = masked.indexOf(k, idx + 1);
      }
    });
    hits.sort((x, y) => x.pos - y.pos);
    const uniq = [];
    hits.forEach(h => { if (!uniq.some(u => u.account.id === h.account.id)) uniq.push(h); });
    return { hits: uniq, masked: masked.trim() };
  }

  function findCategory(seg, categories, kind) {
    let best = null;
    const padded = ' ' + seg + ' ';
    categories.filter(c => c.kind === kind).forEach(c => {
      (c.keywords || []).concat([c.name]).forEach(raw => {
        const k = normalize(raw);
        if (!k) return;
        // يسمح بـ "ال" و"ب" و"و" و"لل" قبل الكلمه
        const re = new RegExp('(^|\\s)(و|ب|ل|لل|ف)?(ال)?' + k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(ات|ين|ه|ي)?(?=\\s|$)');
        if (re.test(padded) && (!best || k.length > best.len)) best = { cat: c, len: k.length };
      });
    });
    return best ? best.cat : null;
  }

  function isoDate(d) {
    const z = n => String(n).padStart(2, '0');
    return d.getFullYear() + '-' + z(d.getMonth() + 1) + '-' + z(d.getDate());
  }

  function detectDate(t, today) {
    const d = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    if (/(^|\s)(اول|قبل) امبارح/.test(t) || /(^|\s)اول امس/.test(t)) d.setDate(d.getDate() - 2);
    else if (/(^|\s)(امبارح|امس|البارح)(\s|$)/.test(t)) d.setDate(d.getDate() - 1);
    return isoDate(d);
  }

  function cleanNote(original) {
    let s = ' ' + original + ' ';
    s = s.replace(/\d+(?:[.,]\d+)?/g, ' ');
    s = s.replace(CURRENCY, ' ');
    const words = s.split(/\s+/).filter(Boolean);
    const filler = new Set(FILLER.concat(['و', 'ال', 'لل', 'ل', 'كمان', 'وكمان']));
    return words.filter(w => !filler.has(normalize(w))).join(' ').trim();
  }

  function splitSegments(t) {
    t = t.replace(/(^|\s)و(?=\d)/g, '$1و ').replace(/(\d)\s+و(?=[^\s\d])/g, '$1 و ');
    let parts = t.split(/\s*[،,؛;]\s*|\s+(?:و|وكمان|كمان|وبعدين|بعدين|ثم)\s+/).map(s => s.trim()).filter(Boolean);
    const hasNum = s => /\d/.test(s);
    if (parts.filter(hasNum).length <= 1) return [t.trim()];
    const merged = [];
    let pending = '';
    parts.forEach((p, i) => {
      if (hasNum(p)) { merged.push((pending ? pending + ' ' : '') + p); pending = ''; return; }
      const next = parts.slice(i + 1).find(hasNum);
      // لو الجزء اللي بعده بيبدأ برقم ("و 50 مواصلات") يبقى الكلام ده تبع اللي قبله
      if (merged.length && !pending && (!next || /^\D{0,12}\d/.test(next) && /^\d/.test(next.replace(/^(دفعت|صرفت|اشتريت|جبت|قبضت)\s+/, '')))) merged[merged.length - 1] += ' ' + p;
      else pending += (pending ? ' ' : '') + p;
    });
    if (pending) {
      if (merged.length) merged[merged.length - 1] += ' ' + pending; else merged.push(pending);
    }
    return merged;
  }

  /**
   * parse("دفعت 120 اكل من الكاش و 50 مواصلات", {accounts, categories, defaultAccountId, today})
   * => [{type, amount, categoryId, accountId, toAccountId, date, note, text}]
   */
  function parse(text, ctx) {
    ctx = ctx || {};
    const accounts = ctx.accounts || [];
    const categories = ctx.categories || [];
    const today = ctx.today || new Date();
    const raw = normalize(text);
    if (!raw) return [];
    const t = wordsToNumbers(raw).replace(CURRENCY, ' $1 ').replace(/\s+/g, ' ').trim();
    const date = detectDate(t, today);
    const globalAcc = findAccounts(t, accounts).hits;
    const globalIncome = INCOME.some(k => new RegExp('(^|\\s)' + k + '(\\s|$)').test(t));

    return splitSegments(t).map(seg => {
      const nums = (seg.match(/\d+(?:\.\d+)?/g) || []).map(Number).filter(n => n > 0);
      const amount = nums.length ? nums[0] : null;
      const { hits, masked } = findAccounts(seg, accounts);
      const has = list => list.some(k => new RegExp('(^|\\s)' + k + '(\\s|$)').test(seg));
      let type = has(INCOME) || (globalIncome && !has(['دفعت', 'صرفت', 'اشتريت'].map(normalize))) ? 'income' : 'expense';
      let accountId = null, toAccountId = null;
      const accs = hits.length ? hits : globalAcc;
      const isTransferVerb = has(TRANSFER);
      if (isTransferVerb && accs.length >= 2) {
        const from = accs.find(h => h.from) || accs.find(h => !h.to) || accs[0];
        const to = accs.find(h => h !== from && h.to) || accs.find(h => h !== from);
        type = 'transfer'; accountId = from.account.id; toAccountId = to.account.id;
      } else if (/(^|\s)سحبت(\s|$)/.test(seg) && accs.length === 1 && accs[0].account.type !== 'cash') {
        const cash = accounts.find(a => a.type === 'cash');
        if (cash) { type = 'transfer'; accountId = accs[0].account.id; toAccountId = cash.id; }
      }
      if (!accountId) accountId = accs.length ? accs[0].account.id : (ctx.defaultAccountId || (accounts[0] && accounts[0].id) || null);

      let categoryId = null;
      if (type !== 'transfer') {
        const cat = findCategory(masked, categories, type);
        const fallback = categories.find(c => c.kind === type && c.fallback) || categories.find(c => c.kind === type);
        categoryId = (cat || fallback || {}).id || null;
      }
      const noteSrc = masked.replace(/(^|\s)من(\s|$)/g, ' ');
      return { type, amount, categoryId, accountId, toAccountId, date, note: cleanNote(noteSrc), text: seg };
    });
  }

  const api = { parse, normalize, wordsToNumbers, splitSegments, cleanNote };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.MasroofyParser = api;
})(typeof window !== 'undefined' ? window : globalThis);
