package com.flutter.ads_plugin.flutter_ads_plugin;

import android.app.Activity;
import android.os.Process;
import android.util.Log;

import androidx.annotation.NonNull;

import com.flutter.ads_plugin.flutter_ads_plugin.interstitial.InterstitialAd;
import com.flutter.ads_plugin.flutter_ads_plugin.reward.RewardAd;
import com.flutter.ads_plugin.flutter_ads_plugin.splash.SplashAd;
import com.flutter.ads_plugin.flutter_ads_plugin.utils.ValueUtils;
import com.flutter.ads_plugin.flutter_ads_plugin.view.BannerViewFlutterPlugin;
import com.flutter.ads_plugin.flutter_ads_plugin.view.FeedViewFlutterPlugin;
import com.hzhj.openads.HJAdsSdk;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class FlutterAdsPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
    private static String hjTag = "HJ######TAG";
    private Activity mActivity;
    private FlutterPluginBinding flutterPluginBinding;
    private MethodChannel methodChannel;
    private ExecutorService executor = Executors.newSingleThreadExecutor();
    private SplashAd splashAd;
    private InterstitialAd interstitialAd;
    private RewardAd rewardAd;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        Log.d(hjTag, "___" + Process.myPid() + "___" + "onAttachedToEngine");
        this.flutterPluginBinding = flutterPluginBinding;
        methodChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_ads_plugin/method");
        methodChannel.setMethodCallHandler(this);
        if (splashAd == null) {
            splashAd = new SplashAd(flutterPluginBinding);
        }
        if (interstitialAd == null) {
            interstitialAd = new InterstitialAd(flutterPluginBinding);
        }
        if (rewardAd == null) {
            rewardAd = new RewardAd(flutterPluginBinding);
        }
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        Log.d(hjTag, "___" + Process.myPid() + "___" + "onMethodCall=" + call.method);
        java.util.Map<String, Object> map = ValueUtils.getValue(call.arguments, new java.util.HashMap<>());
        if (call.method.equals("init")) {
            String initId = ValueUtils.getString(map.get("initId"));
            // 合规开关由 Flutter 侧传入（生产 debug 必须 false；个性化推荐
            // 与成年人标记按用户选择/隐私政策配置），不再硬编码
            boolean debugEnable = Boolean.TRUE.equals(map.get("debugEnable"));
            boolean personalizedAdOn = !Boolean.FALSE.equals(map.get("personalizedAdOn"));
            boolean adult = !Boolean.FALSE.equals(map.get("adult"));
            HJAdsSdk hjAdsSdk = HJAdsSdk.sharedAds();
            hjAdsSdk.setAdult(adult);
            hjAdsSdk.setDebugEnable(debugEnable);
            hjAdsSdk.setPersonalizedAdvertisingOn(personalizedAdOn);
            hjAdsSdk.startWithAppId(mActivity.getApplication(), initId);
            result.success(null);
        } else if (call.method.equals("loadSplash")) {
            if (splashAd != null) {
                String codeId = ValueUtils.getString(map.get("codeId"));
                splashAd.initHJAdsSdkSplash(mActivity, codeId);
                splashAd.loadAdOnly();
            }
            result.success(null);
        } else if (call.method.equals("showSplash")) {
            if (splashAd != null) {
                splashAd.showAd(mActivity);
            }
            result.success(null);
        } else if (call.method.equals("loadAndShowSplash")) {
            if (splashAd != null) {
                String codeId = ValueUtils.getString(map.get("codeId"));
                splashAd.initHJAdsSdkSplash(mActivity, codeId);
                splashAd.loadAndShow(mActivity);
            }
            result.success(null);
        } else if (call.method.equals("loadInterstitial")) {
            if (interstitialAd != null) {
                String codeId = ValueUtils.getString(map.get("codeId"));
                interstitialAd.initHJAdsSdkInterstitial(mActivity, codeId);
                interstitialAd.loadAd();
            }
            result.success(null);
        } else if (call.method.equals("showInterstitial")) {
            if (interstitialAd != null) {
                interstitialAd.showAd(mActivity);
            }
            result.success(null);
        } else if (call.method.equals("loadReward")) {
            if (rewardAd != null) {
                String codeId = ValueUtils.getString(map.get("codeId"));
                String userId = ValueUtils.getString(map.get("userId"));
                Map option = (Map) map.get("option");
                Object nonceObj = map.get("nonce");
                long nonce = nonceObj instanceof Number ? ((Number) nonceObj).longValue() : 0;
                rewardAd.initHJAdsSdkReward(mActivity, codeId, userId, option, nonce);
                rewardAd.loadAd();
            }
            result.success(null);
        } else if (call.method.equals("showReward")) {
            boolean shown = false;
            if (rewardAd != null) {
                Map option = (Map) map.get("option");
                HashMap option2 = new HashMap();
                if (option != null) {
                    option2.putAll(option);
                }
                shown = rewardAd.showAd(option2);
            }
            // 返回是否真正调起：未 ready 时 Flutter 侧立即走失败分支，不会傻等
            result.success(shown);
        } else if (call.method.equals("log")) {
            String msg = ValueUtils.getString(map.get("msg"));
            Log.d(hjTag, "___" + Process.myPid() + "___" + "FLUTTER=" + msg);
            result.success(null);
        } else {
            result.notImplemented();
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        Log.d(hjTag, "___" + Process.myPid() + "___" + "onDetachedFromEngine");
        methodChannel.setMethodCallHandler(null);
        if (splashAd != null) {
            splashAd.setStreamHandler();
            splashAd = null;
        }
        if (interstitialAd != null) {
            interstitialAd.setStreamHandler();
            interstitialAd = null;
        }
        if (rewardAd != null) {
            rewardAd.setStreamHandler();
            rewardAd = null;
        }
        executor.shutdown();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding activityPluginBinding) {
        mActivity = activityPluginBinding.getActivity();
        FeedViewFlutterPlugin.registerWith(mActivity, flutterPluginBinding);
        BannerViewFlutterPlugin.registerWith(mActivity, flutterPluginBinding);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {

    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding activityPluginBinding) {

    }

    @Override
    public void onDetachedFromActivity() {

    }
}
