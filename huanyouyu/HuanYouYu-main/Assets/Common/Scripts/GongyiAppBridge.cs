// 公益中转站 App 桥接（C# 侧）
// 放置路径：Assets/Common/Scripts/GongyiAppBridge.cs
//
// 用法（以贪吃蛇死亡复活为例）：
//   1. 场景里挂一个常驻 GameObject（如 "GongyiAppBridge"），Awake 时自动注册接收器；
//   2. 死亡结算界面点"看视频复活"按钮时调用：
//        GongyiAppBridge.Instance.RequestReward("snake", "revive", onResult: r => {
//            if (r == "earned") ReviveFromLastSafePosition();
//            else CloseReviveDialogOnly(); // dismissed/failed 只恢复 UI，不给奖励
//        });
//   3. 每关最多调用一次由游戏侧自行控制（见产品规则）。
//
// 隔离铁律：本桥只发 game_reward_request，绝不涉及账户余额/任务/每日次数。
using System;
using System.Collections.Generic;
using UnityEngine;
#if UNITY_WEBGL && !UNITY_EDITOR
using System.Runtime.InteropServices;
#endif

public class GongyiAppBridge : MonoBehaviour
{
#if UNITY_WEBGL && !UNITY_EDITOR
    [DllImport("__Internal")] private static extern void GongyiSendToApp(string json);
    [DllImport("__Internal")] private static extern void GongyiRegisterReceiver(string gameObjectName);
    [DllImport("__Internal")] private static extern int GongyiIsInApp();
#endif

    public static GongyiAppBridge Instance { get; private set; }

    /// 场景无需手动挂载：启动时自动创建常驻单例
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Bootstrap()
    {
        if (Instance != null) return;
        var go = new GameObject("GongyiAppBridge");
        go.AddComponent<GongyiAppBridge>();
    }

    // requestId -> 回调。一次请求只消费一次；迟到/重复回执直接丢弃。
    private readonly Dictionary<string, Action<string>> _pending = new();
    private readonly HashSet<string> _consumed = new();

    [Serializable] private class RewardRequest
    {
        public string type = "game_reward_request";
        public string requestId;
        public string gameId;
        public string recoveryType;
    }

    [Serializable] private class RewardResult
    {
        public string type;
        public string requestId;
        public string result;   // earned | dismissed | failed
        public string transId;
    }

    private void Awake()
    {
        if (Instance != null) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);
#if UNITY_WEBGL && !UNITY_EDITOR
        GongyiRegisterReceiver(gameObject.name);
#endif
    }

    /// 是否运行在公益中转站 App 内（不在 App 内时补救按钮应隐藏）
    public bool IsInApp
    {
        get
        {
#if UNITY_WEBGL && !UNITY_EDITOR
            return GongyiIsInApp() == 1;
#else
            return false;
#endif
        }
    }

    /// 请求补救广告。onResult 参数为 "earned" | "dismissed" | "failed"。
    /// 只有 earned 才允许修改本局状态；其余只恢复 UI。
    public void RequestReward(string gameId, string recoveryType, Action<string> onResult)
    {
        if (!IsInApp) { onResult?.Invoke("failed"); return; }
        string requestId = $"req_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{UnityEngine.Random.Range(100000, 999999)}";
        _pending[requestId] = onResult;
        var req = new RewardRequest { requestId = requestId, gameId = gameId, recoveryType = recoveryType };
#if UNITY_WEBGL && !UNITY_EDITOR
        GongyiSendToApp(JsonUtility.ToJson(req));
#else
        onResult?.Invoke("failed");
#endif
    }

    // Flutter 经 jslib SendMessage 到这里
    public void OnAppMessage(string json)
    {
        RewardResult msg;
        try { msg = JsonUtility.FromJson<RewardResult>(json); }
        catch { return; }
        if (msg == null || msg.type != "game_reward_result" || string.IsNullOrEmpty(msg.requestId)) return;
        // 双端只消费一次：不是本端发出的、或已消费过的回执一律丢弃
        if (_consumed.Contains(msg.requestId)) return;
        if (!_pending.TryGetValue(msg.requestId, out var callback)) return;
        _consumed.Add(msg.requestId);
        _pending.Remove(msg.requestId);
        callback?.Invoke(msg.result == "earned" ? "earned"
            : msg.result == "dismissed" ? "dismissed" : "failed");
    }
}
