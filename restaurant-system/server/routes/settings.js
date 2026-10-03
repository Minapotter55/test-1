const express = require('express');
const { all, setSetting } = require('../db');
const { requirePerm } = require('../auth');
const { str } = require('../util');
const realtime = require('../realtime');

const router = express.Router();
const KEYS = ['restaurant_name', 'currency', 'restaurant_phone', 'receipt_footer'];

function readSettings() {
  const out = {};
  for (const r of all('SELECT key, value FROM settings')) if (KEYS.includes(r.key)) out[r.key] = r.value;
  return out;
}

router.get('/', (req, res) => res.json(readSettings()));

router.put('/', requirePerm('settings.manage'), (req, res) => {
  for (const k of KEYS) {
    if (req.body[k] !== undefined) setSetting(k, str(req.body[k], k, { max: 300 }));
  }
  const s = readSettings();
  realtime.emitAll('settings:changed', s);
  res.json(s);
});

module.exports = { router, readSettings };
