package kr.personal.oscalert;

import android.app.Application;

import androidx.appcompat.app.AppCompatDelegate;

import com.google.android.material.color.DynamicColors;

public class OscApp extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        // Always the light theme, whatever the phone's dark-mode setting.
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_NO);
        // Wallpaper-based colors on Android 12+; the brand palette elsewhere.
        DynamicColors.applyToActivitiesIfAvailable(this);
    }
}
