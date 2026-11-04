package com.monchosos.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ignora toques cuando otra app dibuja encima (tapjacking).
        window.decorView.filterTouchesWhenObscured = true
    }
}
