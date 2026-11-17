package com.masroofy.app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.widget.RemoteViews;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** ويدجت الشاشه الرئيسيه: صرف النهارده والشهر، وزرار مايك وزرار إضافه */
public class MasroofyWidget extends AppWidgetProvider {
    static final String PREFS = "masroofy_widget";

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        manager.updateAppWidget(ids, build(context));
    }

    static void refreshAll(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, MasroofyWidget.class));
        if (ids != null && ids.length > 0) manager.updateAppWidget(ids, build(context));
    }

    static RemoteViews build(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
        String day = p.getString("day", "");
        String month = p.getString("month", "");
        // لو اليوم أو الشهر اتغير والتطبيق متفتحش، الأرقام القديمه متتعرضش على إنها بتاعة النهارده
        boolean sameDay = today.equals(day);
        boolean sameMonth = !month.isEmpty() && today.startsWith(month);

        RemoteViews v = new RemoteViews(context.getPackageName(), R.layout.widget_masroofy);
        v.setTextViewText(R.id.w_today, sameDay ? p.getString("todayText", "0") : "0");
        v.setTextViewText(R.id.w_currency, p.getString("currency", "ج.م"));
        v.setTextViewText(R.id.w_line2, sameMonth ? p.getString("line2", "") : "افتح التطبيق عشان يتحدث");
        v.setOnClickPendingIntent(R.id.w_root, open(context, "open", 1));
        v.setOnClickPendingIntent(R.id.w_add, open(context, "add", 2));
        v.setOnClickPendingIntent(R.id.w_mic, open(context, "voice", 3));
        return v;
    }

    static PendingIntent open(Context context, String action, int code) {
        Intent i = new Intent(context, MainActivity.class);
        i.setAction(Intent.ACTION_VIEW);
        i.setData(Uri.parse("masroofy://" + action));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
