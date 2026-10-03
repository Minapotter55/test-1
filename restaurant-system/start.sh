#!/usr/bin/env bash
# تشغيل السيستم على ماك / لينكس
cd "$(dirname "$0")"
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js مش متسطب. نزله من https://nodejs.org (إصدار 22 أو أحدث)"
  exit 1
fi
[ -d node_modules ] || npm install --omit=dev
( sleep 2; (command -v open >/dev/null && open http://localhost:3000) || (command -v xdg-open >/dev/null && xdg-open http://localhost:3000) ) >/dev/null 2>&1 &
npm start
