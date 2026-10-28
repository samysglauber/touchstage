package com.airmidi.controller;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity implements MidiNetworkManager.ConnectionListener, NetworkDiscovery.DiscoveryListener {

    private MidiSurfaceView surfaceView;
    private MidiNetworkManager networkManager;
    private NetworkDiscovery discovery;
    private SettingsModal settingsModal;
    private SharedPreferences prefs;

    private static final String PREF_MAC_IP = "pref_mac_ip";
    private static final String PREF_PORT = "pref_port";
    private static final String PREF_DEVICE_NAME = "pref_device_name";
    public static final String PREF_SIDEBAR_LANDSCAPE = "pref_sidebar_landscape";
    public static final String PREF_SIDEBAR_PORTRAIT = "pref_sidebar_portrait";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Keep screen on during music performance
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        // Fullscreen
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);

        // Allow app to extend edge-to-edge across display cutouts (camera hole / notch)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            WindowManager.LayoutParams lp = getWindow().getAttributes();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
            } else {
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            }
            getWindow().setAttributes(lp);
        }

        prefs = getSharedPreferences("touchstage_native_prefs", Context.MODE_PRIVATE);
        if (!prefs.contains(PREF_MAC_IP)) {
            SharedPreferences legacy = getSharedPreferences("airmidi_native_prefs", Context.MODE_PRIVATE);
            if (legacy.contains(PREF_MAC_IP)) {
                prefs.edit()
                    .putString(PREF_MAC_IP, legacy.getString(PREF_MAC_IP, ""))
                    .putInt(PREF_PORT, legacy.getInt(PREF_PORT, 9000))
                    .putString(PREF_DEVICE_NAME, legacy.getString(PREF_DEVICE_NAME, "Phone"))
                    .apply();
            }
        }
        String savedHost = prefs.getString(PREF_MAC_IP, "");
        int savedPort = prefs.getInt(PREF_PORT, 9000);
        String deviceName = prefs.getString(PREF_DEVICE_NAME, Build.MODEL != null ? Build.MODEL : "Phone");
        String landscapePos = prefs.getString(PREF_SIDEBAR_LANDSCAPE, "right");
        String portraitPos = prefs.getString(PREF_SIDEBAR_PORTRAIT, "bottom");

        // 1. Midi Surface View (Full screen, zero UI clutter, minimalist corner indicator)
        surfaceView = new MidiSurfaceView(this);
        surfaceView.setSidebarPositions(landscapePos, portraitPos);
        setContentView(surfaceView);

        // 2. Load active layout state (or fallback to bundled default layout)
        LayoutModel activeLayout = LayoutModel.loadActiveLayoutState(this);
        if (activeLayout == null) {
            activeLayout = LayoutModel.loadFromAsset(this, "default_layout.json");
        }
        if (activeLayout != null) {
            applyLayout(activeLayout);
        }

        // 3. Settings Modal
        settingsModal = new SettingsModal(this, new SettingsModal.SettingsListener() {
            @Override
            public void onDeviceSelected(String host, int port) {
                prefs.edit().putString(PREF_MAC_IP, host).putInt(PREF_PORT, port).apply();
                settingsModal.setConnectedHost(host);
                surfaceView.setConnectionState(false, true);
                networkManager.updateHost(host, port);
                hideSystemUI();
            }

            @Override
            public void onPresetSelected(PresetManager.PresetItem presetItem) {
                LayoutModel p = PresetManager.loadPreset(MainActivity.this, presetItem);
                if (p != null) {
                    applyLayout(p);
                }
                hideSystemUI();
            }

            @Override
            public void onDeviceNameChanged(String newName) {
                prefs.edit().putString(PREF_DEVICE_NAME, newName).apply();
                if (networkManager != null) {
                    networkManager.setDeviceName(newName);
                }
            }

            @Override
            public void onSidebarPositionChanged(String newLandscapePos, String newPortraitPos) {
                prefs.edit()
                    .putString(PREF_SIDEBAR_LANDSCAPE, newLandscapePos)
                    .putString(PREF_SIDEBAR_PORTRAIT, newPortraitPos)
                    .apply();
                surfaceView.setSidebarPositions(newLandscapePos, newPortraitPos);
            }
        });
        settingsModal.setConnectedHost(savedHost);
        settingsModal.setSidebarPositions(landscapePos, portraitPos);

        // Corner gear button click -> open settings
        surfaceView.setOnSettingsClickedListener(this::openSettings);

        // 4. Network Manager
        networkManager = new MidiNetworkManager(savedHost, savedPort, this);
        networkManager.setDeviceName(deviceName);
        surfaceView.setNetworkManager(networkManager);

        // 5. Network Discovery (Auto-detects Mac Bridge on local Wi-Fi!)
        discovery = new NetworkDiscovery(this);
        discovery.start();

        hideSystemUI();

        // 6. Connect
        if (!savedHost.isEmpty()) {
            surfaceView.setConnectionState(false, true);
            networkManager.connect();
        } else {
            surfaceView.setConnectionState(false, false);
            // Open settings on first launch so user sees discovered Mac immediately
            surfaceView.postDelayed(this::openSettings, 400);
        }
    }

    private void openSettings() {
        String currentName = prefs.getString(PREF_DEVICE_NAME, Build.MODEL != null ? Build.MODEL : "Phone");
        String lPos = prefs.getString(PREF_SIDEBAR_LANDSCAPE, "right");
        String pPos = prefs.getString(PREF_SIDEBAR_PORTRAIT, "bottom");
        settingsModal.show(discovery.getDevices(), currentName, lPos, pPos);
    }

    @Override
    public void onDevicesUpdated(java.util.List<NetworkDiscovery.DiscoveredDevice> devices) {
        settingsModal.updateDevices(devices);

        // If not connected and no host set, auto-connect to the first discovered AirMIDI Bridge!
        String savedHost = prefs.getString(PREF_MAC_IP, "");
        if (savedHost.isEmpty() && !devices.isEmpty() && !networkManager.isConnected()) {
            NetworkDiscovery.DiscoveredDevice first = devices.get(0);
            prefs.edit().putString(PREF_MAC_IP, first.host).putInt(PREF_PORT, first.port).apply();
            settingsModal.setConnectedHost(first.host);
            surfaceView.setConnectionState(false, true);
            networkManager.updateHost(first.host, first.port);
        }
    }

    @Override
    public void onConnectionStateChanged(boolean connected, String message) {
        surfaceView.setConnectionState(connected, false);
        if (connected) {
            String currentName = prefs.getString(PREF_DEVICE_NAME, Build.MODEL != null ? Build.MODEL : "Phone");
            networkManager.setDeviceName(currentName);
            networkManager.sendMidi(0, 0, 0); // wake up
        }
    }

    @Override
    public void onLayoutReceived(final LayoutModel layout) {
        if (layout == null || isFinishing()) return;
        showLayoutSyncPrompt(layout);
    }

    private void showLayoutSyncPrompt(final LayoutModel layout) {
        final boolean hasSavedPreset = PresetManager.hasPreset(this, layout.name);

        final Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(22), dp(20), dp(22), dp(22));

        GradientDrawable bg = new GradientDrawable();
        bg.setShape(GradientDrawable.RECTANGLE);
        bg.setCornerRadius(dp(16));
        bg.setColor(Color.parseColor("#1C1C1E"));
        bg.setStroke(dp(1), Color.parseColor("#2C2C2E"));
        root.setBackground(bg);

        // Title
        TextView title = new TextView(this);
        title.setText(hasSavedPreset ? "Atualizar Layout" : "Novo Layout Recebido");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        // Subtitle
        TextView sub = new TextView(this);
        String name = layout.name != null ? layout.name : "Custom";
        int count = layout.controls != null ? layout.controls.size() : 0;
        int screens = layout.pages != null ? layout.pages.size() : 1;
        String desc = (screens > 1) ? ("\" (" + screens + " telas, " + count + " controles)") : ("\" (" + count + " controles)");
        sub.setText("O Mac sincronizou o layout \"" + name + desc + ".\nDeseja carregar este layout?");
        sub.setTextColor(Color.parseColor("#8E8E93"));
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, dp(10), 0, dp(18));
        root.addView(sub);

        // Button 1: Save and Apply (or Apply if already saved)
        TextView btnSaveAndApply = new TextView(this);
        btnSaveAndApply.setText(hasSavedPreset ? "Atualizar Layout" : "Atualizar e Salvar Preset");
        btnSaveAndApply.setTextColor(Color.WHITE);
        btnSaveAndApply.setTypeface(Typeface.DEFAULT_BOLD);
        btnSaveAndApply.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        btnSaveAndApply.setGravity(Gravity.CENTER);
        btnSaveAndApply.setPadding(dp(14), dp(12), dp(14), dp(12));
        btnSaveAndApply.setBackground(createButtonBg(Color.parseColor("#0A84FF"))); // Apple system blue
        btnSaveAndApply.setOnClickListener(v -> {
            PresetManager.savePreset(MainActivity.this, layout);
            applyLayout(layout);
            dialog.dismiss();
            hideSystemUI();
        });
        root.addView(btnSaveAndApply);

        // Button 2: Only Apply (if not already saved)
        if (!hasSavedPreset) {
            TextView btnOnlyApply = new TextView(this);
            btnOnlyApply.setText("Apenas Carregar sem Salvar");
            btnOnlyApply.setTextColor(Color.WHITE);
            btnOnlyApply.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
            btnOnlyApply.setGravity(Gravity.CENTER);
            btnOnlyApply.setPadding(dp(14), dp(12), dp(14), dp(12));
            LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            );
            p.topMargin = dp(8);
            btnOnlyApply.setLayoutParams(p);
            btnOnlyApply.setBackground(createButtonBg(Color.parseColor("#2C2C2E")));
            btnOnlyApply.setOnClickListener(v -> {
                applyLayout(layout);
                dialog.dismiss();
                hideSystemUI();
            });
            root.addView(btnOnlyApply);
        }

        // Button 3: Cancel
        TextView btnCancel = new TextView(this);
        btnCancel.setText("Cancelar");
        btnCancel.setTextColor(Color.parseColor("#8E8E93"));
        btnCancel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        btnCancel.setGravity(Gravity.CENTER);
        btnCancel.setPadding(dp(12), dp(10), dp(12), dp(8));
        LinearLayout.LayoutParams cancelP = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        );
        cancelP.topMargin = dp(6);
        btnCancel.setLayoutParams(cancelP);
        btnCancel.setOnClickListener(v -> {
            dialog.dismiss();
            hideSystemUI();
        });
        root.addView(btnCancel);

        dialog.setContentView(root);
        dialog.setOnDismissListener(d -> hideSystemUI());
        int width = (int) (getResources().getDisplayMetrics().widthPixels * 0.85f);
        int maxWidth = dp(420);
        if (width > maxWidth) width = maxWidth;
        if (dialog.getWindow() != null) {
            dialog.getWindow().setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
        }
        dialog.show();
    }

    public void applyLayout(LayoutModel layout) {
        if (layout == null) return;
        boolean isPortrait = (layout.canvasHeight > layout.canvasWidth);
        setRequestedOrientation(isPortrait ? ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT : ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
        if (surfaceView != null) {
            surfaceView.setLayout(layout);
            surfaceView.saveStateNow();
        }
    }

    private GradientDrawable createButtonBg(int color) {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setCornerRadius(dp(8));
        d.setColor(color);
        return d;
    }

    private int dp(float val) {
        return (int) TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, val, getResources().getDisplayMetrics()
        );
    }

    @Override
    public void onMidiReceived(int status, int data1, int data2) {
        if (surfaceView != null) {
            surfaceView.updateControlFromMidi(status, data1, data2);
        }
    }

    @Override
    public void onMidiActivity() {
        if (surfaceView != null) {
            surfaceView.flashMidiLed();
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            hideSystemUI();
        }
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        hideSystemUI();
    }

    public void hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Window window = getWindow();
            window.setDecorFitsSystemWindows(false);
            WindowInsetsController controller = window.getInsetsController();
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN
            );
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (surfaceView != null) {
            surfaceView.saveStateNow();
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (surfaceView != null) {
            surfaceView.saveStateNow();
        }
    }

    @Override
    public void onBackPressed() {
        openSettings();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (discovery != null) discovery.stop();
        if (networkManager != null) networkManager.disconnect();
    }
}
