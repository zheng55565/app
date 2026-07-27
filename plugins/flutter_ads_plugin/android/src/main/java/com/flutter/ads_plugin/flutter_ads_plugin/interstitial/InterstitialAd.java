package com.flutter.ads_plugin.flutter_ads_plugin.interstitial;

import android.app.Activity;
import android.os.Process;
import android.util.Log;

import com.hzhj.openads.HJAdsSdkInterstitial;
import com.hzhj.openads.domain.HJAdError;
import com.hzhj.openads.listener.HJOnAdsSdkInterstitialListener;
import com.hzhj.openads.req.HJInterstitialAdRequest;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

public class InterstitialAd implements EventChannel.StreamHandler {
    private static String hjTag = "HJ######TAG";
    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private HJAdsSdkInterstitial hjAdsSdkInterstitial;

    public InterstitialAd(FlutterPlugin.FlutterPluginBinding flutterPluginBinding) {
        eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_ads_plugin/events_InterstitialAd");
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
        if (hjAdsSdkInterstitial != null) {
            hjAdsSdkInterstitial.destroy();
            hjAdsSdkInterstitial = null;
        }
    }

    public void loadAd() {
        if (hjAdsSdkInterstitial != null) {
            hjAdsSdkInterstitial.loadAd();
        }
    }

    public void showAd(Activity mActivity) {
        if (hjAdsSdkInterstitial != null && hjAdsSdkInterstitial.isReady()) {
            hjAdsSdkInterstitial.show(mActivity, null);
        }
    }

    public void initHJAdsSdkInterstitial(Activity mActivity, String codeId) {
        if (hjAdsSdkInterstitial != null) {
            return;
        }
        HJInterstitialAdRequest hjInterstitialAdRequest = new HJInterstitialAdRequest(codeId, null, null);
        hjAdsSdkInterstitial = new HJAdsSdkInterstitial(mActivity, hjInterstitialAdRequest, new HJOnAdsSdkInterstitialListener() {
            @Override
            public void onInterstitialAdLoadSuccess(String placementId) {//广告成功加载。参数说明：placementId（广告位Id）。
                Log.d(hjTag, "___" + Process.myPid() + "___" + "interstitial" + "_" + "onInterstitialAdLoadSuccess=" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onInterstitialAdLoadSuccess");
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                    //eventSink.endOfStream();
                }
            }

            @Override
            public void onInterstitialAdPlayStart() {//广告成功展示，媒体可在此记录曝光。参数说明：adInfo（广告信息，具体可看其内部成员变量）。
                Log.d(hjTag, "___" + Process.myPid() + "___" + "interstitial" + "_" + "onInterstitialAdPlayStart");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onInterstitialAdPlayStart");
                if (eventSink != null) {
                    eventSink.success(result);
                    //eventSink.endOfStream();
                }
            }

            @Override
            public void onInterstitialAdPlayEnd() {//广告播放结束。
                Log.d(hjTag, "___" + Process.myPid() + "___" + "interstitial" + "_" + "onInterstitialAdPlayEnd");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onInterstitialAdPlayEnd");
                if (eventSink != null) {
                    eventSink.success(result);
                    //eventSink.endOfStream();
                }
            }

            @Override
            public void onInterstitialAdClicked() {//广告被点击。
                Log.d(hjTag, "___" + Process.myPid() + "___" + "interstitial" + "_" + "onInterstitialAdClicked");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onInterstitialAdClicked");
                if (eventSink != null) {
                    eventSink.success(result);
                    //eventSink.endOfStream();
                }
            }

            @Override
            public void onInterstitialAdClosed() {//广告关闭。
                Log.d(hjTag, "___" + Process.myPid() + "___" + "interstitial" + "_" + "onInterstitialAdClosed");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onInterstitialAdClosed");
                if (eventSink != null) {
                    eventSink.success(result);
                    eventSink.endOfStream();
                }
            }

            @Override
            public void onInterstitialAdLoadError(HJAdError hjAdError, String placementId) {//广告加载失败。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
                Log.d(hjTag, "___" + Process.myPid() + "___" + "interstitial" + "_" + "onInterstitialAdLoadError=" + hjAdError.code + ":" + hjAdError.msg + ":" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onInterstitialAdLoadError");
                result.put("code", hjAdError.code);
                result.put("msg", hjAdError.msg);
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                    eventSink.endOfStream();
                }
            }

            @Override
            public void onInterstitialAdPlayError(HJAdError hjAdError, String placementId) {//广告播放出错。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
                Log.d(hjTag, "___" + Process.myPid() + "___" + "interstitial" + "_" + "onInterstitialAdPlayError=" + hjAdError.code + ":" + hjAdError.msg + ":" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("event", "onInterstitialAdPlayError");
                result.put("code", hjAdError.code);
                result.put("msg", hjAdError.msg);
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                    eventSink.endOfStream();
                }
            }
        });
    }
}
