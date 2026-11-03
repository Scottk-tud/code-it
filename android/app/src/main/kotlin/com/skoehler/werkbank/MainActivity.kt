package com.skoehler.werkbank

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var senke: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "werkbank/tastatur")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    senke = events
                    melden(resources.configuration)
                }

                override fun onCancel(arguments: Any?) {
                    senke = null
                }
            })
    }

    // Das Manifest führt keyboard|keyboardHidden in configChanges, deshalb kommt
    // das An- und Abstecken hier an, statt die Activity neu zu starten.
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        melden(newConfig)
    }

    private fun melden(konfiguration: Configuration) {
        val vorhanden = konfiguration.keyboard == Configuration.KEYBOARD_QWERTY &&
            konfiguration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO
        senke?.success(vorhanden)
    }
}
