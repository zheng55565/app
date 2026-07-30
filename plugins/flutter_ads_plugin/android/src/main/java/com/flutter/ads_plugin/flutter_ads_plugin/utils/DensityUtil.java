package com.flutter.ads_plugin.flutter_ads_plugin.utils;

import android.content.Context;
import android.util.DisplayMetrics;
import android.util.TypedValue;

public class DensityUtil {
    private DensityUtil() {
        throw new UnsupportedOperationException("cannot be instantiated");
    }

    public static int dp2px(Context var0, float var1) {
        if (var0 == null) {
            return 0;
        } else {
            DisplayMetrics var2 = var0.getResources().getDisplayMetrics();
            return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, var1, var2);
        }
    }

    public static int sp2px(Context var0, float var1) {
        if (var0 == null) {
            return 0;
        } else {
            DisplayMetrics var2 = var0.getResources().getDisplayMetrics();
            return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, var1, var2);
        }
    }

    public static float px2dp(Context var0, float var1) {
        return var0 == null ? 0.0F : var1 / var0.getResources().getDisplayMetrics().density;
    }

    public static float px2sp(Context var0, float var1) {
        return var0 == null ? 0.0F : var1 / var0.getResources().getDisplayMetrics().scaledDensity;
    }
}
