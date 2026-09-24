package kr.personal.oscalert;

import android.app.Application;

import com.google.android.material.color.DynamicColors;

public class OscApp extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        Settings.applyTheme(this);
        // Wallpaper-based colors on Android 12+; the brand palette elsewhere.
        DynamicColors.applyToActivitiesIfAvailable(this);
    }
}
