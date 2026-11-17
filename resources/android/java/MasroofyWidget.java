package com.masroofy.app;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.ArrayMap;
import android.util.SizeF;
import android.view.View;
import android.widget.RemoteViews;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.Map;

/**
 * ويدجت الشاشه الرئيسيه. بيتكبّر ويتصغّر، وشكله بيتغير حسب الحجم:
 * صغير (مايك + صرف النهارده)، متوسط (+ الشهر وزرار الإضافه)، كبير (+ الميزانيه وأرصدة الحسابات).
 */
public class MasroofyWidget extends AppWidgetProvider {
    static final String PREFS = "masroofy_widget";
    static final Class<?>[] KINDS = { MasroofyWidget.class, MasroofyWidgetSmall.class, MasroofyWidgetLarge.class };

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) manager.updateAppWidget(id, views(context, manager, id));
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager, int id, Bundle options) {
        manager.updateAppWidget(id, views(context, manager, id));
    }

    static void refreshAll(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        for (Class<?> kind : KINDS) {
            int[] ids = manager.getAppWidgetIds(new ComponentName(context, kind));
            if (ids == null) continue;
            for (int id : ids) manager.updateAppWidget(id, views(context, manager, id));
        }
    }

    static RemoteViews views(Context context, AppWidgetManager manager, int id) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // أندرويد 12 وأحدث: النظام بيختار الشكل اللي يناسب الحجم وانت بتكبّر وتصغّر
            Map<SizeF, RemoteViews> map = new ArrayMap<>();
            map.put(new SizeF(40f, 40f), fill(context, R.layout.widget_small));
            map.put(new SizeF(220f, 40f), fill(context, R.layout.widget_masroofy));
            map.put(new SizeF(220f, 130f), fill(context, R.layout.widget_large));
            return new RemoteViews(map);
        }
        Bundle o = manager.getAppWidgetOptions(id);
        int w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250);
        int h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 70);
        int layout = (w >= 220 && h >= 130) ? R.layout.widget_large : (w >= 220 ? R.layout.widget_masroofy : R.layout.widget_small);
        return fill(context, layout);
    }

    static RemoteViews fill(Context context, int layout) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
        String day = p.getString("day", "");
        String month = p.getString("month", "");
        // لو اليوم أو الشهر اتغير والتطبيق متفتحش، الأرقام القديمه متتعرضش على إنها بتاعة النهارده
        boolean sameDay = today.equals(day);
        boolean sameMonth = !month.isEmpty() && today.startsWith(month);

        RemoteViews v = new RemoteViews(context.getPackageName(), layout);
        v.setTextViewText(R.id.w_today, sameDay ? p.getString("todayText", "0") : "0");
        v.setOnClickPendingIntent(R.id.w_root, open(context, "open", 1));
        v.setOnClickPendingIntent(R.id.w_mic, open(context, "voice", 3));
        if (layout == R.layout.widget_small) return v;

        v.setTextViewText(R.id.w_currency, p.getString("currency", "ج.م"));
        v.setTextViewText(R.id.w_line2, sameMonth ? p.getString("line2", "") : "افتح التطبيق عشان يتحدث");
        v.setOnClickPendingIntent(R.id.w_add, open(context, "add", 2));
        if (layout != R.layout.widget_large) return v;

        v.setTextViewText(R.id.w_date, sameDay ? p.getString("dateText", "صرفت النهارده") : "صرفت النهارده");
        int pct = parseInt(p.getString("budgetPct", "-1"));
        if (sameMonth && pct >= 0) {
            v.setViewVisibility(R.id.w_progress, View.VISIBLE);
            v.setProgressBar(R.id.w_progress, 100, Math.min(100, pct), false);
        } else {
            v.setViewVisibility(R.id.w_progress, View.GONE);
        }
        int[][] cells = {
            { R.id.w_acc1, R.id.w_acc1n, R.id.w_acc1v },
            { R.id.w_acc2, R.id.w_acc2n, R.id.w_acc2v },
            { R.id.w_acc3, R.id.w_acc3n, R.id.w_acc3v }
        };
        for (int i = 0; i < cells.length; i++) {
            String name = p.getString("acc" + (i + 1) + "n", "");
            if (name.isEmpty()) {
                v.setViewVisibility(cells[i][0], View.GONE);
            } else {
                v.setViewVisibility(cells[i][0], View.VISIBLE);
                v.setTextViewText(cells[i][1], name);
                v.setTextViewText(cells[i][2], p.getString("acc" + (i + 1) + "v", ""));
            }
        }
        return v;
    }

    static int parseInt(String s) {
        try { return Integer.parseInt(s); } catch (Exception e) { return -1; }
    }

    static PendingIntent open(Context context, String action, int code) {
        Intent i = new Intent(context, MainActivity.class);
        i.setAction(Intent.ACTION_VIEW);
        i.setData(Uri.parse("masroofy://" + action));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
