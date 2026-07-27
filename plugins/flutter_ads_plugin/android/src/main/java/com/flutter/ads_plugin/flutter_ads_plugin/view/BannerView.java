package com.flutter.ads_plugin.flutter_ads_plugin.view;

import android.app.Activity;
import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import com.flutter.ads_plugin.flutter_ads_plugin.utils.DensityUtil;
import com.hzhj.openads.HJAdsSdkBanner;
import com.hzhj.openads.domain.HJAdError;
import com.hzhj.openads.listener.HJOnAdsSdkBannerListener;
import com.hzhj.openads.req.HJBannerAdRequest;

import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;

public class BannerView implements PlatformView, MethodChannel.MethodCallHandler {
    private View myNativeView;
    private HJAdsSdkBanner hjAdsSdkBanner;

    BannerView(Activity activity, Context context, BinaryMessenger messenger, int id, Map<String, Object> params) {
        int width = 0;
        int height = 0;
        if (params.containsKey("width")) {
            width = (int) params.get("width");
        }
        if (params.containsKey("height")) {
            height = (int) params.get("height");
        }
        FrameLayout container = new FrameLayout(context);
        container.setLayoutParams(new ViewGroup.LayoutParams(DensityUtil.dp2px(context, width), DensityUtil.dp2px(context, height)));
        this.myNativeView = container;
        String codeId = (String) params.get("codeId");
        loadBanner(activity, container, codeId, width, height);
        MethodChannel methodChannel = new MethodChannel(messenger, "flutter_ads_plugin/bannerview_" + id);
        methodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(MethodCall methodCall, MethodChannel.Result result) {
        // 在接口的回调方法中可以接收到来自Flutter的调用
    }

    @Override
    public View getView() {
        return myNativeView;
    }

    @Override
    public void dispose() {

    }

    private void loadBanner(Activity context, FrameLayout container, String codeId, float width, float height) {
        android.util.Log.d("banner____", "loadBanner");
        hjAdsSdkBanner = new HJAdsSdkBanner(context, new HJOnAdsSdkBannerListener() {
            @Override
            public void onAdLoadSuccess(String s) {
                if (hjAdsSdkBanner.isReady()) {
                    hjAdsSdkBanner.showAd(container);
                }
            }

            @Override
            public void onAdLoadError(HJAdError hjAdError, String s) {

            }

            @Override
            public void onAdShown() {

            }

            @Override
            public void onAdClicked() {

            }

            @Override
            public void onAdClosed() {

            }

            @Override
            public void onAdAutoRefreshed() {

            }

            @Override
            public void onAdAutoRefreshFail(HJAdError hjAdError, String s) {

            }
        });
        HJBannerAdRequest hjBannerAdRequest = new HJBannerAdRequest(codeId, null, null);
        hjAdsSdkBanner.loadAd(hjBannerAdRequest);
    }
}
