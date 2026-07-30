package com.flutter.ads_plugin.flutter_ads_plugin.utils;

import android.util.Log;

import com.hzhj.openads.core.HJAdManger;

public class HJLog {
    private static String LOG = "HJ-log";
    public static void d(String msg) {
        if (isDebug())
            Log.d(LOG, msg);
    }

    public static void simple(String msg) {
        if (isDebug())
            Log.d(LOG, "[S] " + msg);
    }

    public static void high(String msg) {
        if (isDebug())
            Log.d(LOG, "[H] " + msg);
    }

    public static void max(String msg) {
        if (isDebug())
            Log.d(LOG, "[A] " + msg);
    }

    public static void devDebug(String msg) {
        if ((HJAdManger.getInstance()).isDev && (HJAdManger.getInstance()).debug)
            Log.d(LOG, "[dev] " + msg);
    }

    public static void devDebugAuto(String msg1, String msg2) {
        try {
            if (isDebug()) {
                if ((HJAdManger.getInstance()).isDev)
                    msg1 = "[dev] " + msg1 + msg2;
                Log.d(LOG, msg1);
            }
        } finally {}
    }

    public static void w(String paramString) {
        if (isDebug())
            Log.w(LOG, paramString);
    }

    public static void e(String paramString) {
        if (isDebug())
            Log.e(LOG, paramString);
    }


    public static boolean isDebug() {
        return HJAdManger.getInstance().debug;
    }
}
