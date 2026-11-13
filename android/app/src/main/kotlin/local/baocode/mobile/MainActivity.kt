package local.baocode.mobile

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // 后台保连接开启时，引擎随前台服务保留；重新打开界面复用它，不新建第二个引擎。
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        BackgroundHost.reusableEngine()

    override fun shouldDestroyEngineWithHost(): Boolean = !BackgroundHost.keepsEngine

    // 复用的引擎视为宿主提供，父类不会再注册一遍插件；每次附着仍会走到这里。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BackgroundHost.attach(this, flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        BackgroundHost.setVisible(this, true)
    }

    override fun onStop() {
        BackgroundHost.setVisible(this, false)
        super.onStop()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (BackgroundHost.handleActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (BackgroundHost.handlePermissionResult(requestCode)) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        BackgroundHost.detach(this, shouldDestroyEngineWithHost())
        super.onDestroy()
    }
}
