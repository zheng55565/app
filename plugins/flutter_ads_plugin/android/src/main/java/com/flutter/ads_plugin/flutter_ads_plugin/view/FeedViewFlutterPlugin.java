package com.flutter.ads_plugin.flutter_ads_plugin.view;

import android.app.Activity;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.platform.PlatformViewRegistry;

public class FeedViewFlutterPlugin {

    public static void registerWith(Activity activity, FlutterPlugin.FlutterPluginBinding binding) {
        PlatformViewRegistry platformViewRegistry = binding.getPlatformViewRegistry();
        platformViewRegistry.registerViewFactory("flutter_ads_plugin/feedview", new FeedViewFactory(activity, binding.getBinaryMessenger()));
    }
}
