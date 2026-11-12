package com.masroofy.app;

import android.Manifest;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.Settings;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;

/** بيقرا رسايل البنوك والمحافظ من صندوق الوارد، وبيبعت أي رساله جديده للتطبيق وهو مفتوح */
@CapacitorPlugin(
    name = "SmsReader",
    permissions = {
        @Permission(alias = "sms", strings = { Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS })
    }
)
public class SmsReaderPlugin extends Plugin {
    static SmsReaderPlugin instance;

    @Override
    public void load() {
        instance = this;
    }

    @Override
    protected void handleOnDestroy() {
        if (instance == this) instance = null;
    }

    @PluginMethod
    public void read(PluginCall call) {
        if (getPermissionState("sms") != PermissionState.GRANTED) {
            call.reject("permission not granted", "PERMISSION");
            return;
        }
        long since = call.getLong("since", 0L);
        int limit = call.getInt("limit", 1000);
        JSArray list = new JSArray();
        Cursor c = null;
        try {
            c = getContext().getContentResolver().query(
                Uri.parse("content://sms/inbox"),
                new String[] { "_id", "address", "body", "date" },
                "date > ?",
                new String[] { String.valueOf(since) },
                "date DESC"
            );
            while (c != null && c.moveToNext() && list.length() < limit) {
                JSObject o = new JSObject();
                o.put("id", c.getString(0));
                o.put("address", c.getString(1));
                o.put("body", c.getString(2));
                o.put("date", c.getLong(3));
                list.put(o);
            }
        } catch (Exception e) {
            call.reject("could not read sms: " + e.getMessage());
            return;
        } finally {
            if (c != null) c.close();
        }
        JSObject ret = new JSObject();
        ret.put("messages", list);
        call.resolve(ret);
    }

    @PluginMethod
    public void openAppSettings(PluginCall call) {
        Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", getContext().getPackageName(), null));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(i);
        call.resolve();
    }

    void onSms(String address, String body, long date) {
        JSObject o = new JSObject();
        o.put("address", address);
        o.put("body", body);
        o.put("date", date);
        notifyListeners("sms", o, true);
    }
}
