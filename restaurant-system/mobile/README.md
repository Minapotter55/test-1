# تطبيق الموبايل (أندرويد / آيفون)

التطبيق ده بيستخدم **نفس واجهة السيستم** (فولدر `public`) ومتغلف كتطبيق حقيقي بـ [Capacitor](https://capacitorjs.com)، فأي تعديل في السيستم بيظهر في التطبيق بعد `npm run sync`.

## المتطلبات
- Node.js 22 أو أحدث
- **أندرويد:** [Android Studio](https://developer.android.com/studio)
- **آيفون:** جهاز Mac عليه Xcode

## خطوات عمل تطبيق الأندرويد (APK)
```bash
cd mobile
npm install
npm run add:android      # أول مرة بس
npm run sync             # كل ما تعدل في الواجهة
npm run open:android     # يفتح المشروع في Android Studio
```
من Android Studio: **Build ← Build Bundle(s) / APK(s) ← Build APK(s)**، والملف هيطلع في:
`mobile/android/app/build/outputs/apk/debug/app-debug.apk`

انقل الملف ده على أي موبايل أندرويد وثبته.

> للرفع على Google Play استخدم **Build ← Generate Signed Bundle**.

## أول تشغيل للتطبيق
في شاشة الدخول هتلاقي خانة **"عنوان السيرفر"**، اكتب فيها عنوان السيرفر، مثلاً:
- لو السيرفر على كمبيوتر في المطعم: `http://192.168.1.10:3000` (العنوان بيظهر لما تشغل السيرفر، والموبايل لازم يكون على نفس الواي فاي)
- لو السيرفر على النت: `https://orders.your-restaurant.com`

التطبيق بيفتكر العنوان بعد كده.

## آيفون
```bash
npm run add:ios
npm run sync
npm run open:ios        # يفتح في Xcode
```

## تغيير اسم التطبيق والأيقونة
- الاسم والـ ID في `capacitor.config.json` (`appName` و `appId`) - غيرهم **قبل** `add:android`.
- الأيقونة: استخدم [@capacitor/assets](https://github.com/ionic-team/capacitor-assets) مع صورة `public/icons/icon-512.png`.
