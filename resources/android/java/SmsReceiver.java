package com.masroofy.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Telephony;
import android.telephony.SmsMessage;

/** أول ما توصل رساله والتطبيق شغال، بتتبعت له على طول. لو مقفول، بيقراها من الوارد أول ما يتفتح */
public class SmsReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) return;
        SmsMessage[] parts = Telephony.Sms.Intents.getMessagesFromIntent(intent);
        if (parts == null || parts.length == 0) return;
        StringBuilder body = new StringBuilder();
        for (SmsMessage p : parts) {
            if (p != null && p.getMessageBody() != null) body.append(p.getMessageBody());
        }
        String address = parts[0].getDisplayOriginatingAddress();
        SmsReaderPlugin plugin = SmsReaderPlugin.instance;
        if (plugin != null) plugin.onSms(address, body.toString(), System.currentTimeMillis());
    }
}
