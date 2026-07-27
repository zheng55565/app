package com.flutter.ads_plugin.flutter_ads_plugin.view;

import android.app.Activity;
import android.content.Context;
import android.os.Process;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.Toast;

import com.flutter.ads_plugin.flutter_ads_plugin.utils.DensityUtil;
import com.hzhj.openads.HjAdsSdkNativeAd;
import com.hzhj.openads.domain.HJAdError;
import com.hzhj.openads.domain.HJNativeAdData;
import com.hzhj.openads.listener.HJOnAdsNativeAdLoadListener;
import com.hzhj.openads.req.HJNativeAdRequest;
import com.mobads.vivatb.natives.WMNativeAdContainer;

import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;

public class FeedView implements PlatformView, MethodChannel.MethodCallHandler {
    private static String hjTag = "HJ######TAG";

    private View myNativeView;
    private HjAdsSdkNativeAd nativeAd;

    FeedView(Activity activity, Context context, BinaryMessenger messenger, int id, Map<String, Object> params) {
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
        loadFeed(activity, container, codeId, width, height);
        MethodChannel methodChannel = new MethodChannel(messenger, "flutter_ads_plugin/feedview_" + id);
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

    private void loadFeed(Activity context, FrameLayout adContainer, String codeId, float width, float height) {
        android.util.Log.d("feed____", "loadFeed");
        HJNativeAdRequest request = new HJNativeAdRequest(codeId, null, 1, null);
        nativeAd = new HjAdsSdkNativeAd(context, request);
        nativeAd.loadAd(new HJOnAdsNativeAdLoadListener() {
            @Override
            public void onError(HJAdError error, String placementId) {
            }

            @Override
            public void onFeedAdLoad(String placementId) {
                Log.d(hjTag, "___" + Process.myPid() + "___" + "onFeedAdLoad");
                List<HJNativeAdData> unifiedADData = nativeAd.getNativeAdDataList();
                if (unifiedADData != null && unifiedADData.size() > 0) {
                    Log.d(hjTag, "___" + Process.myPid() + "___" + "unifiedADData.size=" + unifiedADData.size());
                    HJNativeAdData nativeAdData = unifiedADData.get(0);
                    /*nativeAdData.setInteractionListener(new HJNativeAdData.NativeAdInteractionListener() {
                        @Override
                        public void onADExposed() {

                        }

                        @Override
                        public void onADClicked() {

                        }

                        @Override
                        public void onADRenderSuccess(View view, float v, float v1) {

                        }

                        @Override
                        public void onADError(HJAdError hjAdError) {

                        }
                    });*/
                    if (nativeAdData.isExpressAd()) {//模版广告
                        nativeAdData.render();
                        View expressAdView = nativeAdData.getExpressAdView();
                        //媒体最终将要展示广告的容器（这里可以直接先addView,也可以在收到onRenderSuccess回调后addView）
                        if (adContainer != null) {
                            adContainer.removeAllViews();
                            adContainer.addView(expressAdView);
                        }
                    }
                }
            }
        });
    }
}
