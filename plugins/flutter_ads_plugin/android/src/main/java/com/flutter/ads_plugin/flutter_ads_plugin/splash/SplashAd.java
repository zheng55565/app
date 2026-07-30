package com.flutter.ads_plugin.flutter_ads_plugin.splash;

import android.app.Activity;
import android.os.Process;
import android.util.Log;
import android.view.ViewGroup;

import com.hzhj.openads.HJAdsSdkSplash;
import com.hzhj.openads.domain.HJAdError;
import com.hzhj.openads.listener.HJOnAdsSdkSplashListener;
import com.hzhj.openads.req.HJSplashAdRequest;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

public class SplashAd implements EventChannel.StreamHandler {
    private static String hjTag = "HJ######TAG";
    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private HJAdsSdkSplash hjAdsSdkSplash;

    public SplashAd(FlutterPlugin.FlutterPluginBinding flutterPluginBinding) {
        eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_ads_plugin/events_SplashAd");
        eventChannel.setStreamHandler(this);
    }

    @Override
    public void onListen(Object o, EventChannel.EventSink eventSink) {
        Log.d(hjTag, "___" + Process.myPid() + "___" + "onListen");
        this.eventSink = eventSink;
        // 模拟发送多个异步事件
        //eventSink.success("success");
        //eventSink.error("error", "中断异常", e.getMessage());
    }

    @Override
    public void onCancel(Object arguments) {
        Log.d(hjTag, "___" + Process.myPid() + "___" + "onCancel");
        this.eventSink = null;
    }

    public void setStreamHandler() {
        eventChannel.setStreamHandler(null);
        if (hjAdsSdkSplash != null) {
            hjAdsSdkSplash.destroy();
            hjAdsSdkSplash = null;
        }
    }

    public void loadAdOnly() {
        if (hjAdsSdkSplash != null) {
            hjAdsSdkSplash.loadAdOnly();
        }
    }

    public void showAd(Activity mActivity) {
        if (hjAdsSdkSplash != null && hjAdsSdkSplash.isReady()) {
            hjAdsSdkSplash.showAd((ViewGroup) mActivity.getWindow().getDecorView());
        }
    }

    public void loadAndShow(Activity mActivity) {
        if (hjAdsSdkSplash != null) {
            hjAdsSdkSplash.loadAndShow((ViewGroup) mActivity.getWindow().getDecorView());
        }
    }

    public void initHJAdsSdkSplash(Activity mActivity, String codeId) {
        if (hjAdsSdkSplash != null) {
            return;
        }
        HJSplashAdRequest hjSplashAdRequest = new HJSplashAdRequest(codeId, null, null);
        hjAdsSdkSplash = new HJAdsSdkSplash(mActivity, hjSplashAdRequest, new HJOnAdsSdkSplashListener() {

            //开屏广告成功展示，媒体可在此记录曝光。
            @Override
            public void onSplashAdSuccessPresent() {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "splash" + "_" + "onSplashAdSuccessPresent");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onSplashAdSuccessPresent");
                if (eventSink != null) {
                    eventSink.success(result);
                    //eventSink.endOfStream();
                }
            }

            //开屏广告成功加载。参数说明：placementId（报错的广告位Id）。
            @Override
            public void onSplashAdSuccessLoad(String placementId) {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "splash" + "_" + "onSplashAdSuccessLoad=" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onSplashAdSuccessLoad");
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                    //eventSink.endOfStream();
                }
            }

            //开屏广告加载失败。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
            @Override
            public void onSplashAdFailToLoad(HJAdError hjAdError, String placementId) {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "splash" + "_" + "onSplashAdFailToLoad=" + hjAdError.code + ":" + hjAdError.msg + ":" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onSplashAdFailToLoad");
                result.put("code", hjAdError.code);
                result.put("msg", hjAdError.msg);
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                    // EventChannel is plugin-scoped and reused by later ad sessions.
                    // Ending it here makes Dart keep a closed subscription forever.
                }
            }

            //开屏广告被点击。
            @Override
            public void onSplashAdClicked() {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "splash" + "_" + "onSplashAdClicked");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onSplashAdClicked");
                if (eventSink != null) {
                    eventSink.success(result);
                    //eventSink.endOfStream();
                }
            }

            //开屏广告关闭。
            @Override
            public void onSplashClosed() {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "splash" + "_" + "onSplashClosed");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onSplashClosed");
                if (eventSink != null) {
                    eventSink.success(result);
                    // Keep the shared event stream alive for a later splash request.
                }
            }
        });
    }
}
