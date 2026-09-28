import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const P = require('../www/parser.js');
const D = require('../www/defaults.js');
const ctx = { accounts: D.accounts, categories: D.categories, defaultAccountId: 'cash', today: new Date(2026, 8, 28) };
let fail = 0;
function check(text, expected) {
  const got = P.parse(text, ctx);
  const ok = expected.length === got.length && expected.every((e, i) => Object.entries(e).every(([k, v]) => got[i][k] === v));
  if (!ok) { fail++; console.log('FAIL', text, '\n  got', JSON.stringify(got.map(g => ({ type: g.type, amount: g.amount, categoryId: g.categoryId, accountId: g.accountId, toAccountId: g.toAccountId, date: g.date, note: g.note })))); }
  else console.log('ok  ', text);
}
check('دفعت 120 جنيه أكل', [{ type: 'expense', amount: 120, categoryId: 'food', accountId: 'cash' }]);
check('اشتريت غدا بمية وخمسين جنيه من فودافون كاش', [{ amount: 150, categoryId: 'food', accountId: 'wallet' }]);
check('اوبر 85 انستاباي', [{ amount: 85, categoryId: 'transport', accountId: 'instapay' }]);
check('دفعت الف وميتين ايجار', [{ amount: 1200, categoryId: 'bills' }]);
check('دفعت ٣٥٠ صيدلية', [{ amount: 350, categoryId: 'health' }]);
check('دفعت 50 مواصلات و 200 اكل', [{ amount: 50, categoryId: 'transport' }, { amount: 200, categoryId: 'food' }]);
check('قهوة 60 و بنزين 400 من الكاش', [{ amount: 60, categoryId: 'food', accountId: 'cash' }, { amount: 400, categoryId: 'transport', accountId: 'cash' }]);
check('قبضت المرتب 15000 على انستاباي', [{ type: 'income', amount: 15000, categoryId: 'salary', accountId: 'instapay' }]);
check('سحبت 2000 من انستاباي', [{ type: 'transfer', amount: 2000, accountId: 'instapay', toAccountId: 'cash' }]);
check('حولت 500 من الكاش للمحفظة', [{ type: 'transfer', amount: 500, accountId: 'cash', toAccountId: 'wallet' }]);
check('امبارح دفعت تلاتين جنيه ميكروباص', [{ amount: 30, categoryId: 'transport', date: '2026-09-27' }]);
check('دفعت الف ونص هدوم', [{ amount: 1500, categoryId: 'shopping' }]);
check('خمسة وعشرين جنيه عيش', [{ amount: 25, categoryId: 'food' }]);
check('شحنت رصيد ب 100', [{ type: 'expense', amount: 100, categoryId: 'bills' }]);
check('دفعت 2.5 الف كورس', [{ amount: 2500, categoryId: 'edu' }]);
check('حاجة غريبة 70', [{ amount: 70, categoryId: 'other' }]);
check('جالي 3000 من عميل على فودافون كاش', [{ type: 'income', amount: 3000, categoryId: 'freelance', accountId: 'wallet' }]);
check('فاتورة الكهربا 430 وفاتورة النت 250', [{ amount: 430, categoryId: 'bills' }, { amount: 250, categoryId: 'bills' }]);
console.log(fail ? `\n${fail} failed` : '\nall passed');
process.exit(fail ? 1 : 0);
