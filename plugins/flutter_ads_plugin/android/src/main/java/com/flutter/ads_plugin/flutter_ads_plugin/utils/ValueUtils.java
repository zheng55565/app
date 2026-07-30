package com.flutter.ads_plugin.flutter_ads_plugin.utils;

import java.math.BigDecimal;


/**
 * 取值工具类
 *
 * @author chenmin 2015-6-19
 */
public class ValueUtils {

    public static <T> T getValue(Object value, T defaultValue) {
        if (value == null || isEmpty(getString(value))) {
            return defaultValue;
        }
        try {
            return (T) value;
        } catch (Exception ignored) {
            return defaultValue;
        }
    }

    public static String getString(Object value) {
        return value == null ? "" : value.toString();
    }

    public static String getString(Object value, String defaultValue) {
        return value == null ? defaultValue : value.toString();
    }

    public static Integer getInt(Object value) {
        return getInt(getString(value), 0);
    }

    public static Integer getInt(Object value, int defaultValue) {
        if (value == null) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value.toString());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public static long getLong(Object value) {
        return getLong(getString(value), 0);
    }

    public static long getLong(Object value, long defaultValue) {
        if (value == null) {
            return defaultValue;
        }
        try {
            return Long.parseLong(value.toString());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public static Float getFloat(Object value) {
        return getFloat(value, 0);
    }

    public static Float getFloat(Object value, float defaultValue) {
        if (value == null) {
            return defaultValue;
        }
        try {
            return Float.parseFloat(value.toString());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public static Double getDouble(Object value) {
        return getDouble(value, 0);
    }

    public static Double getDouble(Object value, double defaultValue) {
        if (value == null) {
            return defaultValue;
        }
        try {
            return Double.parseDouble(value.toString());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    public static Boolean getBoolean(Object value) {
        if (value == null) {
            return false;
        }
        return Boolean.valueOf(value.toString());
    }

    public static String toDecimal(Object value, int decimal) {
        if (value == null || "".equals(value.toString().trim())) {
            BigDecimal bd = new BigDecimal("0");
            bd = bd.setScale(decimal, BigDecimal.ROUND_HALF_UP);
            return bd.toString();
        }
        try {
            BigDecimal bd = new BigDecimal(value.toString());
            bd = bd.setScale(decimal, BigDecimal.ROUND_HALF_UP);
            return bd.toString();
        } catch (Exception e) {
            BigDecimal bd = new BigDecimal("0");
            bd = bd.setScale(decimal, BigDecimal.ROUND_HALF_UP);
            return bd.toString();
        }
    }

    public static String getStatInt(int value, int length) {
        int n = 1;
        for (int i = 1; i < length; i++) {
            n = n * 10;
        }
        int le = length - getString(value).length();
        StringBuilder s = new StringBuilder(toDecimal(value, 0));
        if (le > 0) {
            for (int i = 0; i < le; i++) {
                s.insert(0, "0");
            }
        }
        return s.toString();
    }

    public static String getPrice(Object value, String unit) {
        String v;
        if (value == null || "".equals(value.toString().trim())) {
            v = "0.00";
        } else {
            try {
                BigDecimal bd = new BigDecimal(value.toString());
                bd = bd.setScale(2, BigDecimal.ROUND_HALF_UP);
                v = bd.toString();
            } catch (Exception e) {
                v = "0.00";
            }
        }
        if (isEmpty(unit)) {
            return v;
        }
        return v + unit;
    }

    public static String getDistance(Object distance) {
        try {
            Double result = Double.parseDouble(distance.toString());
            if (result > 1000) {
                result /= 1000.0;
                BigDecimal bd = new BigDecimal(result);
                bd = bd.setScale(1, BigDecimal.ROUND_HALF_UP);
                return bd + " 千米";
            } else {
                return result.intValue() + " 米";
            }
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * 判断字符串是否为null或长度为0
     *
     * @param s 待校验字符串
     * @return {@code true}: 空<br> {@code false}: 不为空
     */
    public static boolean isEmpty(CharSequence s) {
        return s == null || s.length() == 0;
    }
}
