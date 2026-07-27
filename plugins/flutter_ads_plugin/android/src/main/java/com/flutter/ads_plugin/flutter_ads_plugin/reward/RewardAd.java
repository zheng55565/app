package com.flutter.ads_plugin.flutter_ads_plugin.reward;

import android.app.Activity;
import android.os.Process;
import android.util.Log;

import com.hzhj.openads.HJAdsSdkReward;
import com.hzhj.openads.HJRewardVerify;
import com.hzhj.openads.domain.HJAdError;
import com.hzhj.openads.listener.HJOnAdsSdkRewardListener;
import com.hzhj.openads.req.HJRewardAdRequest;

import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;

public class RewardAd implements EventChannel.StreamHandler {
    private static String hjTag = "HJ######TAG";
    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private HJAdsSdkReward hjAdsSdkReward;
    // 当前实例的参数指纹：codeId/userId/option 任一变化都销毁重建，
    // 支持首页/小游戏双广告位切换
    private String currentCodeId;
    private String currentUserId;
    private Map currentOption;
    // 会话 nonce：Dart 每次 loadReward 下发并自增，事件回带后由 Dart 过滤
    // 旧会话的迟到/重复事件（EventChannel 队列里的事件 destroy 挡不住）。
    // 用数组做 holder 让监听器闭包按【创建时的实例】捕获：旧实例迟到事件
    // 永远带旧 nonce，不会读到新会话的值
    private long[] nonceHolder = new long[]{0};

    public RewardAd(FlutterPlugin.FlutterPluginBinding flutterPluginBinding) {
        eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_ads_plugin/events_RewardAd");
        eventChannel.setStreamHandler(this);
    }

    @Override
    public void onListen(Object o, EventChannel.EventSink eventSink) {
        Log.d(hjTag, "___" + Process.myPid() + "___" + "onListen");
        this.eventSink = eventSink;
    }

    @Override
    public void onCancel(Object arguments) {
        Log.d(hjTag, "___" + Process.myPid() + "___" + "onCancel");
        this.eventSink = null;
    }

    public void setStreamHandler() {
        eventChannel.setStreamHandler(null);
        destroyAd();
    }

    private void destroyAd() {
        if (hjAdsSdkReward != null) {
            hjAdsSdkReward.destroy();
            hjAdsSdkReward = null;
        }
        currentCodeId = null;
        currentUserId = null;
        currentOption = null;
    }

    public void loadAd() {
        if (hjAdsSdkReward != null) {
            hjAdsSdkReward.loadAd();
        }
    }

    /** 展示广告。返回是否真正调起（未 ready 返回 false，Flutter 侧据此立即失败而非傻等）。 */
    public boolean showAd(HashMap option) {
        if (hjAdsSdkReward != null && hjAdsSdkReward.isReady()) {
            hjAdsSdkReward.show(option);
            return true;
        }
        Log.d(hjTag, "___" + Process.myPid() + "___" + "reward showAd: not ready");
        return false;
    }

    public boolean isReady() {
        return hjAdsSdkReward != null && hjAdsSdkReward.isReady();
    }

    public void initHJAdsSdkReward(Activity mActivity, String codeId, String userId, Map option, long nonce) {
        // 参数不变则复用现有实例（继续用已加载未消费的广告）；变化则销毁重建
        if (hjAdsSdkReward != null
                && Objects.equals(currentCodeId, codeId)
                && Objects.equals(currentUserId, userId)
                && Objects.equals(currentOption, option)) {
            nonceHolder[0] = nonce; // 复用实例：更新会话 nonce，新事件带新值
            return;
        }
        destroyAd();
        currentCodeId = codeId;
        currentUserId = userId;
        currentOption = option == null ? null : new HashMap(option);
        // 新实例配新 holder；旧实例监听器仍持有旧 holder，迟到事件带旧 nonce
        final long[] holder = new long[]{nonce};
        nonceHolder = holder;
        HJRewardAdRequest hjRewardAdRequest = new HJRewardAdRequest(codeId, userId, option);
        hjAdsSdkReward = new HJAdsSdkReward(mActivity, mActivity, hjRewardAdRequest, new HJOnAdsSdkRewardListener() {
            @Override
            public void onVideoAdLoadSuccess(String placementId) {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoAdLoadSuccess=" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoAdLoadSuccess");
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }

            @Override
            public void onVideoAdPlayEnd() {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoAdPlayEnd");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoAdPlayEnd");
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }

            @Override
            public void onVideoAdPlayStart() {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoAdPlayStart");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoAdPlayStart");
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }

            @Override
            public void onVideoAdClicked() {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoAdClicked");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoAdClicked");
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }

            @Override
            public void onVideoRewarded(String transId, HJRewardVerify hjRewardVerify) {
                // isReward 是广告平台的真实发奖判定，必须透传给 Flutter；
                // 只有 isReward=true 才允许上层按"看完"处理
                boolean isReward = hjRewardVerify != null && hjRewardVerify.isReward();
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoRewarded transId=" + transId + " isReward=" + isReward);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoRewarded");
                result.put("transId", transId);
                result.put("isReward", isReward);
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }

            @Override
            public void onVideoAdClosed() {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoAdClosed");
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoAdClosed");
                // 不调用 endOfStream：EventChannel 是插件级长连接，结束流会
                // 让后续广告事件全部丢失
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }

            @Override
            public void onVideoAdLoadError(HJAdError hjAdError, String placementId) {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoAdLoadError=" + hjAdError.code + ":" + hjAdError.msg + ":" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoAdLoadError");
                result.put("code", hjAdError.code);
                result.put("msg", hjAdError.msg);
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }

            @Override
            public void onVideoAdPlayError(HJAdError hjAdError, String placementId) {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "reward" + "_" + "onVideoAdPlayError=" + hjAdError.code + ":" + hjAdError.msg + ":" + placementId);
                java.util.Map<String, Object> result = new java.util.HashMap<>();
                result.put("nonce", holder[0]);
                result.put("event", "onVideoAdPlayError");
                result.put("code", hjAdError.code);
                result.put("msg", hjAdError.msg);
                result.put("placementId", placementId);
                if (eventSink != null) {
                    eventSink.success(result);
                }
            }
        });
    }
}
