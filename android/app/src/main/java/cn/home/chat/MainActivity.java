package cn.home.chat;

import android.content.SharedPreferences;
import android.net.*;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.*;

/** Android-only upgrade import and routing. All product features live in Dart/plugins. */
public class MainActivity extends FlutterActivity {
    @Override public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "cn.home.chat/legacy").setMethodCallHandler((call, result) -> {
            try {
                if (call.method.equals("readLegacy")) {
                    SharedPreferences saved = getPreferences(0);
                    TokenStore secrets = new TokenStore(this);
                    Map<String, Object> data = new HashMap<>();
                    data.put("base", saved.getString("base", "")); data.put("workspace", saved.getString("workspace", ""));
                    data.put("voice_mode", saved.getBoolean("voice_mode", false)); data.put("sessions", saved.getString("sessions_v2", ""));
                    data.put("files_dir", getFilesDir().getPath()); data.put("token", secrets.read()); data.put("aliyun", secrets.read("aliyun"));
                    result.success(data);
                } else if (call.method.equals("bindWifi")) {
                    ConnectivityManager manager = (ConnectivityManager)getSystemService(CONNECTIVITY_SERVICE);
                    for (Network network : manager.getAllNetworks()) {
                        NetworkCapabilities capabilities = manager.getNetworkCapabilities(network);
                        if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                            result.success(manager.bindProcessToNetwork(network)); return;
                        }
                    }
                    result.success(false);
                } else result.notImplemented();
            } catch (Exception error) {
                result.error("legacy", "无法导入旧版加密设置；旧数据已保留，请重新打开应用或检查设置", null);
            }
        });
    }
}
