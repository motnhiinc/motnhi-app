package com.storybookar.storybook_ar

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var scanAnyPageBridges: ScanAnyPageBridges? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        scanAnyPageBridges = ScanAnyPageBridges.register(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        scanAnyPageBridges?.onActivityResult(requestCode, resultCode, data)
    }

    // ArCoreApk.requestInstall() hands its outcome back on resume, not through an activity
    // result, so the reader bridge needs a resume signal to finish an install it started.
    override fun onPostResume() {
        super.onPostResume()
        scanAnyPageBridges?.onHostResume()
    }
}
