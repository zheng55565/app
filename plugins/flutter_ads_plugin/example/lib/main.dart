import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ads_plugin/flutter_ads_plugin.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _flutterAdsPlugin = FlutterAdsPlugin();

  @override
  void initState() {
    super.initState();
    initAd();
  }

  //初始化广告
  Future<void> initAd() async {
    _flutterAdsPlugin.logd("initAd");
    _flutterAdsPlugin.initAd('174334');
    setState(() {});
  }

  //load开屏广告
  Future<void> loadSplash() async {
    _flutterAdsPlugin.logd("loadSplash");
    _flutterAdsPlugin.loadSplash(
      '9178873326955476',
      onSplashAdSuccessPresent: () {//开屏广告成功展示，媒体可在此记录曝光。
        _flutterAdsPlugin.logd("loadSplash_onSplashAdSuccessPresent");
      },
      onSplashAdSuccessLoad: (String placementId) {//开屏广告成功加载。参数说明：placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadSplash_onSplashAdSuccessLoad=" + placementId);
        //开屏广告成功加载回调中播放这条开屏广告
        showSplash();
      },
      onSplashAdFailToLoad: (String code, String msg, String placementId) {//开屏广告加载失败。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadSplash_onSplashAdFailToLoad=" + code + ":" + msg + ":" + placementId);
      },
      onSplashAdClicked: () {//开屏广告被点击。
        _flutterAdsPlugin.logd("loadSplash_onSplashAdClicked");
      },
      onSplashClosed: () {//开屏广告关闭。
        _flutterAdsPlugin.logd("loadSplash_onSplashClosed");
      },
    );
    setState(() {});
  }

  //show开屏广告
  Future<void> showSplash() async {
    _flutterAdsPlugin.logd("showSplash");
    _flutterAdsPlugin.showSplash();
    setState(() {});
  }

  //loadAndShow开屏广告
  Future<void> loadAndShowSplash() async {
    _flutterAdsPlugin.logd("loadAndShowSplash");
    _flutterAdsPlugin.loadAndShowSplash(
      '9178873326955476',
      onSplashAdSuccessPresent: () {//开屏广告成功展示，媒体可在此记录曝光。
        _flutterAdsPlugin.logd("loadAndShowSplash_onSplashAdSuccessPresent");
      },
      onSplashAdSuccessLoad: (String placementId) {//开屏广告成功加载。参数说明：placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadAndShowSplash_onSplashAdSuccessLoad=" + placementId);
      },
      onSplashAdFailToLoad: (String code, String msg, String placementId) {//开屏广告加载失败。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadAndShowSplash_onSplashAdFailToLoad=" + code + ":" + msg + ":" + placementId);
      },
      onSplashAdClicked: () {//开屏广告被点击。
        _flutterAdsPlugin.logd("loadAndShowSplash_onSplashAdClicked");
      },
      onSplashClosed: () {//开屏广告关闭。
        _flutterAdsPlugin.logd("loadAndShowSplash_onSplashClosed");
      },
    );
    setState(() {});
  }

  //load插屏广告
  Future<void> loadInterstitial() async {
    _flutterAdsPlugin.logd("loadInterstitial");
    _flutterAdsPlugin.loadInterstitial(
      '7921135964545941',
      onInterstitialAdLoadSuccess: (String placementId) {//广告成功加载。参数说明：placementId（广告位Id）。
        _flutterAdsPlugin.logd("loadInterstitial_onInterstitialAdLoadSuccess=" + placementId);
        //广告成功加载回调中播放这条广告
        showInterstitial();
      },
      onInterstitialAdPlayStart: () {//广告成功展示，媒体可在此记录曝光。参数说明：adInfo（广告信息，具体可看其内部成员变量）。
        _flutterAdsPlugin.logd("loadInterstitial_onInterstitialAdPlayStart");
      },
      onInterstitialAdPlayEnd: () {//广告播放结束。
        _flutterAdsPlugin.logd("loadInterstitial_onInterstitialAdPlayEnd");
      },
      onInterstitialAdClicked: () {//广告被点击。
        _flutterAdsPlugin.logd("loadInterstitial_onInterstitialAdClicked");
      },
      onInterstitialAdClosed: () {//广告关闭。
        _flutterAdsPlugin.logd("loadInterstitial_onInterstitialAdClosed");
      },
      onInterstitialAdLoadError: (String code, String msg, String placementId) {//广告加载失败。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadInterstitial_onInterstitialAdLoadError=" + code + ":" + msg + ":" + placementId);
      },
      onInterstitialAdPlayError: (String code, String msg, String placementId) {//广告播放出错。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadInterstitial_onInterstitialAdPlayError=" + code + ":" + msg + ":" + placementId);
      },
    );
    setState(() {});
  }

  //show插屏广告
  Future<void> showInterstitial() async {
    _flutterAdsPlugin.logd("showInterstitial");
    _flutterAdsPlugin.showInterstitial();
    setState(() {});
  }

  //load激励视频广告
  Future<void> loadReward() async {
    Map<String, dynamic> option = {
      'test': 'test',
    };
    _flutterAdsPlugin.logd("loadReward");
    _flutterAdsPlugin.loadReward(
      '5870225444210928',
      'userId',
      option,
      onVideoAdLoadSuccess: (String placementId) {//广告成功加载。参数说明：placementId（广告位Id）。
        _flutterAdsPlugin.logd("loadReward_onVideoAdLoadSuccess=" + placementId);
        //广告成功加载回调中播放这条广告
        showReward();
      },
      onVideoAdPlayEnd: () {//广告播放结束。
        _flutterAdsPlugin.logd("loadReward_onVideoAdPlayEnd");
      },
      onVideoAdPlayStart: () {//广告成功展示，媒体可在此记录曝光。
        _flutterAdsPlugin.logd("loadReward_onVideoAdPlayStart");
      },
      onVideoAdClicked: () {//广告被点击。
        _flutterAdsPlugin.logd("loadReward_onVideoAdClicked");
      },
      onVideoRewarded: (String transId, bool isReward) {//广告获取奖励。isReward 为平台发奖判定。
        _flutterAdsPlugin.logd("loadReward_onVideoRewarded=$transId isReward=$isReward");
      },
      onVideoAdClosed: () {//广告关闭。
        _flutterAdsPlugin.logd("loadReward_onVideoAdClosed");
      },
      onVideoAdLoadError: (String code, String msg, String placementId) {//广告加载失败。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadReward_onVideoAdLoadError=" + code + ":" + msg + ":" + placementId);
      },
      onVideoAdPlayError: (String code, String msg, String placementId) {//广告播放出错。参数说明：error（报错信息，具体可看其内部code和message）、placementId（报错的广告位Id）。
        _flutterAdsPlugin.logd("loadReward_onVideoAdPlayError=" + code + ":" + msg + ":" + placementId);
      },
    );
    setState(() {});
  }

  //show激励视频广告
  Future<void> showReward() async {
    _flutterAdsPlugin.logd("showReward");
    Map<String, dynamic> option = {
      "func_type": 1,
      "key": "888"
    };
    _flutterAdsPlugin.showReward(option);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 350,
                height: 200,
                color: Colors.red,
                child: AndroidView(
                  viewType: 'flutter_ads_plugin/feedview',
                  creationParams: const {
                    "codeId": "4714663972050724",
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                ),
              ),
              ElevatedButton(
                child: const Text('开屏广告load和show分开调用方法'),
                onPressed: () async {
                  await loadSplash();
                },
              ),
              ElevatedButton(
                child: const Text('插屏广告'),
                onPressed: () async {
                  await loadInterstitial();
                },
              ),
              ElevatedButton(
                child: const Text('激励视频广告'),
                onPressed: () async {
                  await loadReward();
                },
              ),
              Container(
                width: 350,
                height: 55,
                color: Colors.red,
                child: AndroidView(
                  viewType: 'flutter_ads_plugin/bannerview',
                  creationParams: const {
                    "codeId": "7677974859977385",
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
