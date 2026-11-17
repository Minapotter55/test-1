package com.masroofy.app;

import android.content.Context;
import android.content.SharedPreferences;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/** التطبيق بيبعت الأرقام هنا بعد كل تعديل، والويدجت بيتحدث على طول */
@CapacitorPlugin(name = "Widget")
public class WidgetPlugin extends Plugin {
    private static final String[] KEYS = { "day", "month", "todayText", "line2", "currency", "dateText", "budgetPct",
        "acc1n", "acc1v", "acc2n", "acc2v", "acc3n", "acc3v" };

    @PluginMethod
    public void update(PluginCall call) {
        SharedPreferences.Editor e = getContext().getSharedPreferences(MasroofyWidget.PREFS, Context.MODE_PRIVATE).edit();
        for (String k : KEYS) {
            String v = call.getString(k);
            if (v != null) e.putString(k, v);
        }
        e.apply();
        MasroofyWidget.refreshAll(getContext());
        call.resolve();
    }
}
