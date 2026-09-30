# Nazzel (نزّل)

تطبيق Android مفتوح المصدر لتنزيل الفيديو والصوت من المواقع، مع متصفح داخلي بيكتشف تدفقات البث (HLS/DASH).
كل المعالجة بتتم على الجهاز باستخدام **yt-dlp** و**FFmpeg**، ومفيش أي خدمة تحليلات.

An open-source Android app for downloading video and audio from websites. yt-dlp and FFmpeg run on the device, and there is no analytics.

## المميزات

| الميزة | التفاصيل |
|---|---|
| اختيار الجودة | أفضل جودة، 4K (2160p)، 1440p، 1080p، 720p، 480p، 360p |
| تفضيل 60FPS | بيختار أعلى frame rate متاح، أو يثبّت على 30 لو الخيار مقفول |
| استخراج الصوت | MP3 / Opus / WAV |
| الترجمة | بينزّل الترجمة (العادية والتلقائية) بلغات تختارها ويدمجها في الفيديو |
| قائمة الانتظار | التنزيلات بتشتغل واحد ورا التاني في الخلفية، والقائمة بتفضل محفوظة لو التطبيق اتقفل |
| إيقاف واستئناف | الإيقاف بيوقف yt-dlp، والاستئناف بيكمّل من الملف الجزئي (`.part`) |
| متصفح داخلي | بيكتشف روابط `.m3u8` و`.mpd` وملفات الفيديو المباشرة لما التحليل العادي يفشل، وفيه حجب إعلانات بسيط |
| المشاركة | Share من أي تطبيق → نزّل، والرابط بيتحلل على طول |
| الخصوصية | التوكنات والكوكيز وقيم الـ query والإيميلات بتتخفي من السجلات ومن "نسخ التشخيص" |
| تحديث yt-dlp | زرار في الإعدادات بيحدّث yt-dlp من غير ما تحتاج إصدار جديد من التطبيق |

الملفات بتتحفظ في `Download/Nazzel` عن طريق MediaStore، فمش محتاج صلاحية تخزين.

## البنية

```
core/   Kotlin/JVM خالص (بيتعمله unit tests):
        YtDlpArgs       خيارات التنزيل → أوامر yt-dlp
        Redactor        إخفاء البيانات الحساسة من السجلات
        StreamDetector  التعرف على HLS / DASH / ملفات الفيديو
        AdBlocker       حجب الإعلانات بالدومين
app/    تطبيق Android (Jetpack Compose)
        engine/Engine       تشغيل yt-dlp وFFmpeg (مكتبة youtubedl-android)
        engine/QueueWorker  WorkManager worker بيمشي على قائمة الانتظار
        engine/MediaExporter نقل الملف النهائي لـ Download/Nazzel
        ui/                 شاشات: تنزيل، القائمة، المتصفح، الإعدادات
```

## البناء

محتاج JDK 17 وAndroid SDK (API 35).

```bash
./gradlew :core:test            # unit tests
./gradlew :app:assembleRelease  # APKs في app/build/outputs/apk/release/
```

فيه APK منفصل لكل معمارية (`arm64-v8a` لمعظم الموبايلات الحديثة)، وكمان APK شامل (`universal`).

GitHub Actions بيبني الـ APKs مع كل push ويرفعها كـ artifact. لو عملت tag زي `v0.1.0` هيتعمل GitHub Release والـ APKs متعلقة فيه.

> نسخة الـ release حاليًا متوقعة بمفتاح debug عشان تتثبت على طول. قبل النشر العام اعمل مفتاح توقيع خاص بيك.

## ملاحظات

- أول تشغيل بياخد كام ثانية عشان يفك Python وFFmpeg.
- المتصفح الداخلي مبني على Android WebView. نسخة VRKA بتستخدم GeckoView وuBlock Origin، وده ممكن نضيفه بعدين لكنه بيكبّر حجم التطبيق حوالي 60–100MB.
- استخدم التطبيق للمحتوى اللي من حقك تنزّله، واحترم شروط المواقع وحقوق النشر.

## الترخيص

GPL-3.0، لأن مكتبة youtubedl-android مرخصة GPL-3.0.
