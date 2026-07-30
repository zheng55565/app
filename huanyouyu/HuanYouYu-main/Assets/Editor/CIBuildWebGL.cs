using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

/// 公益中转站 App 的标准 WebGL 无头构建入口。
/// 用法：
///   Tuanjie.exe -batchmode -quit -projectPath <项目> \
///     -executeMethod CIBuildWebGL.BuildWebGL -customBuildPath <输出目录> -logFile <日志>
/// 产物直接部署到 App 后端的 /games/ 静态目录即可（模板已暴露
/// window.unityInstance，供 GongyiAppBridge.jslib 桥接回执使用）。
public static class CIBuildWebGL
{
    public static void BuildWebGL()
    {
        string outputPath = GetCommandLineArg("-customBuildPath");
        if (string.IsNullOrWhiteSpace(outputPath))
        {
            outputPath = Path.Combine(Directory.GetCurrentDirectory(), "Builds", "WebGL");
        }
        string fullOutputPath = Path.GetFullPath(outputPath);
        Directory.CreateDirectory(fullOutputPath);

        string[] scenes = EditorBuildSettings.scenes
            .Where(s => s.enabled)
            .Select(s => s.path)
            .ToArray();
        if (scenes.Length == 0)
        {
            throw new InvalidOperationException("EditorBuildSettings 中没有启用的场景。");
        }

        // 移动端 WebView 内运行的关键配置
        PlayerSettings.WebGL.template = "PROJECT:GongyiApp"; // 自定义模板，暴露 unityInstance
        PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Gzip;
        PlayerSettings.WebGL.decompressionFallback = true;   // 静态托管无需配 Content-Encoding 头
        PlayerSettings.WebGL.exceptionSupport = WebGLExceptionSupport.ExplicitlyThrownExceptionsOnly;
        PlayerSettings.runInBackground = false;
        PlayerSettings.colorSpace = ColorSpace.Gamma;        // 与微信小游戏构建一致，避免移动端 WebGL1 兼容问题

        var options = new BuildPlayerOptions
        {
            scenes = scenes,
            locationPathName = fullOutputPath,
            target = BuildTarget.WebGL,
            options = BuildOptions.None,
        };

        var report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
        {
            throw new Exception("WebGL build failed: " + report.summary.result +
                                ", errors=" + report.summary.totalErrors);
        }
        Debug.Log("WebGL build succeeded: " + fullOutputPath +
                  " size=" + report.summary.totalSize);
    }

    private static string GetCommandLineArg(string key)
    {
        string[] args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], key, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }
        return string.Empty;
    }
}
