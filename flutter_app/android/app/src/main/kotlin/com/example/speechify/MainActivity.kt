package com.example.speechify

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Désactive le mode edge-to-edge forcé par Android 15
        // Empêche le contenu de passer derrière la barre de navigation Samsung
        WindowCompat.setDecorFitsSystemWindows(window, true)
    }
}
