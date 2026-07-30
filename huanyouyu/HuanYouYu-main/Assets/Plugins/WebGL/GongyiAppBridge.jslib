// 公益中转站 App 桥接插件（Unity WebGL）
// 放置路径：Assets/Plugins/WebGL/GongyiAppBridge.jslib
//
// 与 Flutter WebView 的协议见 D:\new-api-app\docs\unity-webgl-bridge.md。
// Unity C# 侧通过 DllImport 调用 GongyiSendToApp 发消息；
// Flutter 回执经 window.onGongyiMessage 转发给指定 GameObject 的
// OnAppMessage(string) 方法（SendMessage）。
mergeInto(LibraryManager.library, {

  // C#: [DllImport("__Internal")] static extern void GongyiSendToApp(string json);
  GongyiSendToApp: function (jsonPtr) {
    var json = UTF8ToString(jsonPtr);
    if (window.GongyiBridge && window.GongyiBridge.postMessage) {
      window.GongyiBridge.postMessage(json);
    } else {
      console.warn('[GongyiBridge] 不在 App WebView 内，消息丢弃:', json);
    }
  },

  // C#: [DllImport("__Internal")] static extern void GongyiRegisterReceiver(string gameObjectName);
  // 注册后，Flutter 发来的每条消息都会 SendMessage 到该 GameObject 的 OnAppMessage(string)
  GongyiRegisterReceiver: function (namePtr) {
    var goName = UTF8ToString(namePtr);
    // unityInstance 未就绪时先入队，就绪后重放——WebGL 模板若忘了把实例
    // 暴露成 window.unityInstance，这里会持续报错而不是静默丢消息
    var queue = [];
    function deliver(json) {
      var inst = window.unityInstance || window.gameInstance;
      if (!inst) {
        console.error('[GongyiBridge] window.unityInstance 未暴露，消息暂存待重放。'
          + '请在 WebGL 模板 createUnityInstance().then 里加：window.unityInstance = instance');
        queue.push(json);
        return;
      }
      try {
        while (queue.length) inst.SendMessage(goName, 'OnAppMessage', queue.shift());
        inst.SendMessage(goName, 'OnAppMessage', json);
      } catch (e) {
        console.error('[GongyiBridge] 转发到 Unity 失败', e);
      }
    }
    window.onGongyiMessage = deliver;
  },

  // C#: [DllImport("__Internal")] static extern bool GongyiIsInApp();
  GongyiIsInApp: function () {
    return (window.GongyiBridge && window.GongyiBridge.postMessage) ? 1 : 0;
  }
});
