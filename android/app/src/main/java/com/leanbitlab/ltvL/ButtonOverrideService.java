/*
 * ForkLauncher
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package com.omeda.arc;

import android.accessibilityservice.AccessibilityService;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.util.Log;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.IntConsumer;

/**
 * Sees remote buttons before the system acts on them, so a button can open an app of the user's choice
 * or do nothing. Buttons the TV maker handles as soon as they arrive (before any accessibility service)
 * can't be changed this way.
 *
 * Overrides live in the "button_overrides" preferences: key code -> package name, where an empty
 * package name means "do nothing".
 */
public class ButtonOverrideService extends AccessibilityService {
    private static final String TAG = "ButtonOverride";
    private static final String PREFS = "button_overrides";

    private static ButtonOverrideService instance;
    private static IntConsumer captureCallback;

    /** Key whose up event belongs to a down event this service already handled. */
    private int swallowUpFor = KeyEvent.KEYCODE_UNKNOWN;

    @Override
    protected void onServiceConnected() {
        instance = this;
    }

    @Override
    public boolean onUnbind(Intent intent) {
        instance = null;
        return super.onUnbind(intent);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        int code = event.getKeyCode();

        if (event.getAction() == KeyEvent.ACTION_UP && code == swallowUpFor) {
            swallowUpFor = KeyEvent.KEYCODE_UNKNOWN;
            return true;
        }
        if (event.getAction() != KeyEvent.ACTION_DOWN) {
            return false;
        }

        if (captureCallback != null) {
            if (isNavigationKey(code)) {
                return false; // Back still cancels, and the settings stay usable
            }
            IntConsumer callback = captureCallback;
            captureCallback = null;
            swallowUpFor = code;
            callback.accept(code);
            return true;
        }

        SharedPreferences prefs = prefs(this);
        String key = String.valueOf(code);
        if (!prefs.contains(key)) {
            return false;
        }
        swallowUpFor = code;
        if (event.getRepeatCount() == 0) {
            String packageName = prefs.getString(key, "");
            if (!packageName.isEmpty()) {
                launch(packageName);
            }
        }
        return true;
    }

    private void launch(String packageName) {
        PackageManager pm = getPackageManager();
        Intent intent = pm.getLeanbackLaunchIntentForPackage(packageName);
        if (intent == null) {
            intent = pm.getLaunchIntentForPackage(packageName);
        }
        if (intent == null) {
            Log.w(TAG, "No launch intent for " + packageName);
            return;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(intent);
        } catch (Exception e) {
            Log.w(TAG, "Could not open " + packageName, e);
        }
    }

    private static boolean isNavigationKey(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_BACK:
            case KeyEvent.KEYCODE_DPAD_UP:
            case KeyEvent.KEYCODE_DPAD_DOWN:
            case KeyEvent.KEYCODE_DPAD_LEFT:
            case KeyEvent.KEYCODE_DPAD_RIGHT:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_HOME:
                return true;
            default:
                return false;
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    // Called from MainActivity's method channel, on the main thread.

    /** Whether the user has turned the service on in the accessibility settings. */
    static boolean isEnabled(Context context) {
        String enabled = Settings.Secure.getString(context.getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled == null) {
            return false;
        }
        ComponentName self = new ComponentName(context, ButtonOverrideService.class);
        for (String entry : enabled.split(":")) {
            ComponentName name = ComponentName.unflattenFromString(entry);
            if (self.equals(name)) {
                return true;
            }
        }
        return false;
    }

    static List<Map<String, Object>> getOverrides(Context context) {
        List<Map<String, Object>> list = new ArrayList<>();
        for (Map.Entry<String, ?> entry : prefs(context).getAll().entrySet()) {
            try {
                int code = Integer.parseInt(entry.getKey());
                Map<String, Object> item = new HashMap<>();
                item.put("keyCode", code);
                item.put("keyName", KeyEvent.keyCodeToString(code));
                item.put("packageName", String.valueOf(entry.getValue()));
                list.add(item);
            } catch (NumberFormatException ignored) {
            }
        }
        return list;
    }

    static void setOverride(Context context, int keyCode, String packageName) {
        prefs(context).edit().putString(String.valueOf(keyCode), packageName == null ? "" : packageName).apply();
    }

    static void removeOverride(Context context, int keyCode) {
        prefs(context).edit().remove(String.valueOf(keyCode)).apply();
    }

    /** Reports the next button pressed. Returns false if the service isn't running. */
    static boolean captureNextButton(IntConsumer callback) {
        if (instance == null) {
            return false;
        }
        cancelCapture();
        captureCallback = callback;
        return true;
    }

    /** Ends a pending capture, reporting -1 to its caller. */
    static void cancelCapture() {
        IntConsumer callback = captureCallback;
        captureCallback = null;
        if (callback != null) {
            callback.accept(-1);
        }
    }
}
