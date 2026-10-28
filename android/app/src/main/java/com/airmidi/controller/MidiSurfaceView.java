package com.airmidi.controller;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.TimeInterpolator;
import android.animation.ValueAnimator;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.BatteryManager;
import android.util.AttributeSet;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.view.animation.PathInterpolator;
import com.airmidi.controller.LayoutModel.PageModel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class MidiSurfaceView extends View {

    private LayoutModel layout;
    private MidiNetworkManager networkManager;
    private Runnable onSettingsClickedListener;

    // Connection state for minimalist corner indicator
    private boolean isConnected = false;
    private boolean isConnecting = false;
    private boolean isMidiActive = false;
    private long lastMidiActivityTime = 0;

    // Vertical Sidebar & Navigation
    private final RectF sidebarRect = new RectF();
    private final RectF settingsButtonRect = new RectF();
    private final RectF tabsButtonRect = new RectF();
    private final RectF batteryRect = new RectF();
    private boolean isTabFlyoutOpen = false;
    private final RectF flyoutCardRect = new RectF();
    private final List<RectF> tabFlyoutItemRects = new ArrayList<>();

    // Sidebar position configuration
    private String sidebarLandscapePos = "right"; // "right" or "left"
    private String sidebarPortraitPos = "bottom";  // "bottom" or "top"
    private float canvasOriginX = 0f;
    private float canvasOriginY = 0f;
    private float availableW = 0f;
    private float availableH = 0f;

    // Asynchronous state persistence (Zero UI latency)
    private static final java.util.concurrent.ExecutorService saveExecutor = java.util.concurrent.Executors.newSingleThreadExecutor();
    private final android.os.Handler saveHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    private final Runnable saveRunnable = () -> {
        if (layout != null) {
            final String json = layout.toJsonString();
            saveExecutor.execute(() -> {
                try {
                    java.io.File dir = getContext().getFilesDir();
                    java.io.File temp = new java.io.File(dir, LayoutModel.ACTIVE_STATE_FILE + ".tmp");
                    java.io.File target = new java.io.File(dir, LayoutModel.ACTIVE_STATE_FILE);
                    java.io.FileOutputStream fos = new java.io.FileOutputStream(temp);
                    fos.write(json.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    fos.flush();
                    fos.close();
                    temp.renameTo(target);
                } catch (Exception ignored) {}
            });
        }
    };

    // Bottom Tab Bar & Slide Transition ("Ease-Ease" Animation)
    private final RectF bottomTabBarRect = new RectF();
    private boolean isBottomSwipeActive = false;
    private int bottomSwipePointerId = -1;
    private float bottomSwipeStartX = 0f;
    private float bottomSwipeStartY = 0f;
    private boolean isDraggingPage = false;
    private float dragInBaseUnits = 0f; // Horizontal shift in base 920-width coordinates

    private boolean isTransitioning = false;
    private int transitionFromIndex = -1;
    private int transitionToIndex = -1;
    private ValueAnimator pageAnimator = null;
    private final TimeInterpolator fluidEaseInterpolator = new DecelerateInterpolator(2.2f);
    private final TimeInterpolator snapBackInterpolator = new DecelerateInterpolator(1.8f);

    // Offscreen cached bitmaps for zero-allocation 120 FPS buttery-smooth page sliding
    private Bitmap transitionFromBitmap = null;
    private Bitmap transitionToBitmap = null;
    private int cachedFromIndex = -1;
    private int cachedToIndex = -1;

    // Battery monitoring
    private int batteryPercent = 100;
    private boolean isBatteryCharging = false;

    // Drawing paints
    private final Paint paintFill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint paintStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint paintText = new Paint(Paint.ANTI_ALIAS_FLAG);

    // Aspect ratio fitting transforms (strictly 18:9)
    private float scale = 1.0f;
    private float offsetX = 0.0f;
    private float offsetY = 0.0f;

    // Multi-touch tracking
    private static class TouchState {
        ControlModel control;
        boolean isBottomButton = false;
        float startY = 0;
        float initialVal = 0;
    }
    private final Map<Integer, TouchState> activeTouches = new HashMap<>();

    public MidiSurfaceView(Context context) {
        super(context);
        init();
    }

    public MidiSurfaceView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    public MidiSurfaceView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init();
    }

    private void init() {
        setBackgroundColor(Color.BLACK);
        paintStroke.setStyle(Paint.Style.STROKE);
        paintText.setTextAlign(Paint.Align.CENTER);
        paintText.setFakeBoldText(true);
    }

    private final BroadcastReceiver batteryReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            updateBattery(intent);
        }
    };

    private void updateBattery(Intent intent) {
        if (intent == null) return;
        int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
        if (level >= 0 && scale > 0) {
            batteryPercent = (int) ((level / (float) scale) * 100);
        }
        isBatteryCharging = (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL);
        invalidate();
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        try {
            IntentFilter filter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
            Intent sticky = getContext().registerReceiver(batteryReceiver, filter);
            updateBattery(sticky);
        } catch (Exception ignored) {}
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        try {
            getContext().unregisterReceiver(batteryReceiver);
        } catch (Exception ignored) {}
        removeCallbacks(vuDecayRunnable);
        isDecayRunning = false;
    }

    public List<ControlModel> getAllControls() {
        List<ControlModel> all = new ArrayList<>();
        if (layout != null) {
            if (layout.pages != null && !layout.pages.isEmpty()) {
                for (LayoutModel.PageModel p : layout.pages) {
                    if (p.controls != null) all.addAll(p.controls);
                }
            } else if (layout.controls != null) {
                all.addAll(layout.controls);
            }
        }
        return all;
    }

    private boolean isDecayRunning = false;

    private final Runnable vuDecayRunnable = new Runnable() {
        @Override
        public void run() {
            boolean anyActive = false;
            List<ControlModel> ctrls = getAllControls();
            for (ControlModel ctrl : ctrls) {
                // If fader is pulled all the way down, force zero immediately
                if ("fader".equals(ctrl.type) && ctrl.value <= ctrl.minValue) {
                    ctrl.vuLevel = 0.0f;
                    ctrl.peakLevel = 0.0f;
                    ctrl.targetVuLevel = 0.0f;
                    continue;
                }

                if (ctrl.vuLevel > 0.002f) {
                    // Studio-grade PPM / VU ballistics:
                    // Proportional release at the top (~10-15% dip between drum beats/transients),
                    // linear tail towards zero so audio stops cleanly in ~600-750ms without hanging.
                    float decay = Math.max(0.018f, ctrl.vuLevel * 0.038f);
                    ctrl.vuLevel = Math.max(0.0f, ctrl.vuLevel - decay);
                    ctrl.peakLevel = Math.max(ctrl.vuLevel, ctrl.peakLevel - 0.02f);
                    anyActive = true;
                } else {
                    ctrl.vuLevel = 0.0f;
                    ctrl.peakLevel = 0.0f;
                }
            }
            if (anyActive) {
                invalidate();
                postDelayed(this, 25); // 40 FPS smooth ballistics
            } else {
                isDecayRunning = false;
                invalidate();
            }
        }
    };

    public void triggerVuDecay() {
        if (!isDecayRunning) {
            isDecayRunning = true;
            post(vuDecayRunnable);
        }
    }

    public void setLayout(LayoutModel layout) {
        this.layout = layout;
        if (pageAnimator != null && pageAnimator.isRunning()) {
            pageAnimator.cancel();
        }
        isTransitioning = false;
        isDraggingPage = false;
        dragInBaseUnits = 0f;
        calculateScaleAndOffsets(getWidth(), getHeight());
        invalidate();
        scheduleStateSave();
    }

    public LayoutModel getLayout() {
        return layout;
    }

    public void setSidebarPositions(String landscapePos, String portraitPos) {
        this.sidebarLandscapePos = (landscapePos != null && landscapePos.equalsIgnoreCase("left")) ? "left" : "right";
        this.sidebarPortraitPos = (portraitPos != null && portraitPos.equalsIgnoreCase("top")) ? "top" : "bottom";
        calculateScaleAndOffsets(getWidth(), getHeight());
        invalidate();
    }

    public void scheduleStateSave() {
        saveHandler.removeCallbacks(saveRunnable);
        saveHandler.postDelayed(saveRunnable, 250);
    }

    public void saveStateNow() {
        saveHandler.removeCallbacks(saveRunnable);
        if (layout != null) {
            LayoutModel.saveLayoutState(getContext(), layout);
        }
    }

    public void setNetworkManager(MidiNetworkManager networkManager) {
        this.networkManager = networkManager;
    }

    public void setOnSettingsClickedListener(Runnable listener) {
        this.onSettingsClickedListener = listener;
    }

    public void setConnectionState(boolean connected, boolean connecting) {
        this.isConnected = connected;
        this.isConnecting = connecting;
        invalidate();
    }

    public void flashMidiLed() {
        this.isMidiActive = true;
        this.lastMidiActivityTime = System.currentTimeMillis();
        postDelayed(() -> {
            if (System.currentTimeMillis() - lastMidiActivityTime >= 80) {
                isMidiActive = false;
                invalidate();
            }
        }, 90);
        invalidate();
    }

    public void updateControlFromMidi(int status, int data1, int data2) {
        if (layout == null) return;

        List<ControlModel> allCtrls = getAllControls();

        int messageType = status & 0xF0;
        int channel = (status & 0x0F) + 1;
        boolean changed = false;

        if (messageType == 0xB0) {
            // Control Change (CC)
            int ccNumber = data1;
            int value = data2;

            for (ControlModel ctrl : allCtrls) {
                if ("fader".equals(ctrl.type)) {
                    if (ctrl.midiChannel == channel && ctrl.midiNumber == ccNumber) {
                        ctrl.value = value;
                        float faderPct = (ctrl.value - ctrl.minValue) / (float)(ctrl.maxValue - ctrl.minValue);
                        if (faderPct <= 0.005f) {
                            ctrl.vuLevel = 0.0f;
                            ctrl.peakLevel = 0.0f;
                            ctrl.targetVuLevel = 0.0f;
                        } else if (ctrl.vuLevel > faderPct) {
                            ctrl.vuLevel = faderPct;
                            ctrl.peakLevel = Math.min(ctrl.peakLevel, faderPct);
                        }
                        changed = true;
                    }
                    if (ctrl.hasVuMeter) {
                        int vCh = (ctrl.vuMidiChannel > 0) ? ctrl.vuMidiChannel : ctrl.midiChannel;
                        int vNum = (ctrl.vuMidiNumber > 0) ? ctrl.vuMidiNumber : ctrl.midiNumber;
                        if (vCh == channel && vNum == ccNumber) {
                            float inLvl = value / 127.0f;
                            ctrl.targetVuLevel = inLvl;
                            if (inLvl > ctrl.vuLevel) {
                                ctrl.vuLevel = inLvl;
                            }
                            if (ctrl.vuLevel > ctrl.peakLevel) ctrl.peakLevel = ctrl.vuLevel;
                            triggerVuDecay();
                            changed = true;
                        }
                    }
                } else if ("vu".equals(ctrl.type)) {
                    int vCh = (ctrl.vuMidiChannel > 0) ? ctrl.vuMidiChannel : ctrl.midiChannel;
                    int vNum = (ctrl.vuMidiNumber > 0) ? ctrl.vuMidiNumber : ctrl.midiNumber;
                    if (vCh == channel && vNum == ccNumber) {
                        float inLvl = value / 127.0f;
                        ctrl.targetVuLevel = inLvl;
                        if (inLvl > ctrl.vuLevel) {
                            ctrl.vuLevel = inLvl;
                        }
                        if (ctrl.vuLevel > ctrl.peakLevel) ctrl.peakLevel = ctrl.vuLevel;
                        triggerVuDecay();
                        changed = true;
                    }
                } else if ("knob".equals(ctrl.type)) {
                    if (ctrl.midiChannel == channel && ctrl.midiNumber == ccNumber) {
                        ctrl.value = value;
                        changed = true;
                    }
                } else if ("xypad".equals(ctrl.type)) {
                    if (ctrl.midiChannel == channel) {
                        if (ccNumber == 1) {
                            ctrl.valueX = value;
                            changed = true;
                        } else if (ccNumber == 2) {
                            ctrl.valueY = value;
                            changed = true;
                        }
                    }
                } else if ("button".equals(ctrl.type) && "cc".equalsIgnoreCase(ctrl.midiType)) {
                    if (ctrl.midiChannel == channel && ctrl.midiNumber == ccNumber) {
                        int onVal = (ctrl.maxValue > 0) ? ctrl.maxValue : 127;
                        int offVal = (ctrl.minValue >= 0) ? ctrl.minValue : 0;
                        int threshold = (onVal + offVal) / 2;
                        boolean wasLit = (ctrl.value > threshold);
                        ctrl.value = value;
                        boolean isLit = (ctrl.value > threshold);
                        ctrl.isMuted = !isLit;
                        syncFaderMuteFromButton(ctrl);
                        if (wasLit != isLit) {
                            animateButtonTrigger(ctrl, isLit);
                        }
                        changed = true;
                    }
                }
            }
        } else if (messageType == 0xD0) {
            // Channel Pressure (Mackie MCU Meter Protocol & Standard Channel Pressure)
            // In Mackie MCU: status is 0xD0 on Channel 1.
            // data1 high nibble is Track 0..7 (Track 1..8).
            // data1 low nibble is Meter Level 0..12 (12 = 0 dB full scale, 14 = clip).
            if (channel == 1) {
                int mcuTrack = ((data1 >> 4) & 0x07) + 1;
                int mcuLevelRaw = (data1 & 0x0F);
                float mcuLevel = (mcuLevelRaw == 0) ? 0.0f : ((mcuLevelRaw >= 14) ? 1.0f : ((float) mcuLevelRaw / 12.0f));

                for (ControlModel ctrl : allCtrls) {
                    if (ctrl.hasVuMeter || "vu".equals(ctrl.type)) {
                        int assignedTrack = (ctrl.vuMidiNumber > 0) ? ctrl.vuMidiNumber : ((ctrl.vuMidiChannel > 0) ? ctrl.vuMidiChannel : ctrl.midiChannel);
                        if (assignedTrack == mcuTrack) {
                            ctrl.targetVuLevel = mcuLevel;
                            if (mcuLevel > ctrl.vuLevel) {
                                ctrl.vuLevel = mcuLevel; // Instant attack on peaks!
                            }
                            if (ctrl.vuLevel > ctrl.peakLevel) ctrl.peakLevel = ctrl.vuLevel;
                            triggerVuDecay();
                            changed = true;
                        }
                    }
                }
            } else if (channel == 2) {
                // Dedicated Master Track VU from AirMIDI script (or Channel Pressure Ch 2)
                int mcuLevelRaw = (data1 & 0x0F);
                float mcuLevel = (data1 > 14) ? (data1 / 127.0f) : ((mcuLevelRaw == 0) ? 0.0f : ((mcuLevelRaw >= 14) ? 1.0f : ((float) mcuLevelRaw / 12.0f)));

                for (ControlModel ctrl : allCtrls) {
                    if (ctrl.hasVuMeter || "vu".equals(ctrl.type)) {
                        boolean isMaster = "vu_master".equals(ctrl.id) ||
                                           (ctrl.label != null && ctrl.label.equalsIgnoreCase("MASTER")) ||
                                           ctrl.vuMidiNumber == 9 ||
                                           (ctrl.vuMidiChannel == 2);
                        if (isMaster) {
                            ctrl.targetVuLevel = mcuLevel;
                            if (mcuLevel > ctrl.vuLevel) {
                                ctrl.vuLevel = mcuLevel; // Instant attack on Master peaks!
                            }
                            if (ctrl.vuLevel > ctrl.peakLevel) ctrl.peakLevel = ctrl.vuLevel;
                            triggerVuDecay();
                            changed = true;
                        }
                    }
                }
            } else {
                // Standard Channel Pressure on channels 3..16
                float standardLevel = data1 / 127.0f;
                for (ControlModel ctrl : allCtrls) {
                    if (ctrl.hasVuMeter || "vu".equals(ctrl.type)) {
                        int targetCh = (ctrl.vuMidiChannel > 0) ? ctrl.vuMidiChannel : ctrl.midiChannel;
                        if (targetCh == channel) {
                            ctrl.targetVuLevel = standardLevel;
                            if (standardLevel > ctrl.vuLevel) {
                                ctrl.vuLevel = standardLevel;
                            }
                            if (ctrl.vuLevel > ctrl.peakLevel) ctrl.peakLevel = ctrl.vuLevel;
                            triggerVuDecay();
                            changed = true;
                        }
                    }
                }
            }
        } else if (messageType == 0xE0) {
            // Pitch Bend: MCU motorized fader feedback
            // Channel 1..8 = Tracks 1..8 Faders, Channel 9 = Master Fader
            int faderVal = data2; // 0..127
            for (ControlModel ctrl : allCtrls) {
                if ("fader".equals(ctrl.type)) {
                    if (channel >= 1 && channel <= 8) {
                        int assignedTrack = (ctrl.vuMidiNumber > 0) ? ctrl.vuMidiNumber : ((ctrl.vuMidiChannel > 0) ? ctrl.vuMidiChannel : ctrl.midiChannel);
                        if (assignedTrack == channel || ("pitchbend".equalsIgnoreCase(ctrl.midiType) && ctrl.midiChannel == channel)) {
                            ctrl.value = faderVal;
                            float faderPct = (ctrl.value - ctrl.minValue) / (float)(ctrl.maxValue - ctrl.minValue);
                            if (faderPct <= 0.005f) {
                                ctrl.vuLevel = 0.0f;
                                ctrl.peakLevel = 0.0f;
                                ctrl.targetVuLevel = 0.0f;
                            } else if (ctrl.vuLevel > faderPct) {
                                ctrl.vuLevel = faderPct;
                                ctrl.peakLevel = Math.min(ctrl.peakLevel, faderPct);
                            }
                            changed = true;
                        }
                    } else if (channel == 9) {
                        boolean isMaster = "fader_master".equals(ctrl.id) ||
                                           (ctrl.label != null && ctrl.label.equalsIgnoreCase("MASTER")) ||
                                           ctrl.vuMidiNumber == 9 ||
                                           ("pitchbend".equalsIgnoreCase(ctrl.midiType) && ctrl.midiChannel == 9);
                        if (isMaster) {
                            ctrl.value = faderVal;
                            float faderPct = (ctrl.value - ctrl.minValue) / (float)(ctrl.maxValue - ctrl.minValue);
                            if (faderPct <= 0.005f) {
                                ctrl.vuLevel = 0.0f;
                                ctrl.peakLevel = 0.0f;
                                ctrl.targetVuLevel = 0.0f;
                            } else if (ctrl.vuLevel > faderPct) {
                                ctrl.vuLevel = faderPct;
                                ctrl.peakLevel = Math.min(ctrl.peakLevel, faderPct);
                            }
                            changed = true;
                        }
                    }
                }
            }
        } else if (messageType == 0x90 || messageType == 0x80) {
            // Note On / Note Off
            int noteNumber = data1;
            int velocity = data2;
            boolean isNoteOn = (messageType == 0x90) && (velocity > 0);

            // 1. Mackie Control Mute Feedback (Notes 16..23 on Channel 1)
            if (channel == 1 && noteNumber >= 16 && noteNumber <= 23) {
                int mcuTrack = (noteNumber - 16) + 1; // Track 1..8
                boolean isMuted = isNoteOn; // In MCU protocol, Note On 127 = Muted, Note Off 0 = Active
                for (ControlModel ctrl : allCtrls) {
                    int assignedTrack = (ctrl.vuMidiNumber > 0) ? ctrl.vuMidiNumber : ((ctrl.vuMidiChannel > 0) ? ctrl.vuMidiChannel : ctrl.midiChannel);
                    if (assignedTrack == mcuTrack) {
                        ctrl.isMuted = isMuted;
                        if (ctrl.hasBottomButton) {
                            ctrl.buttonValue = !isMuted;
                        }
                        changed = true;
                    }
                    if ("button".equals(ctrl.type)) {
                        if (ctrl.id != null && (ctrl.id.contains("btn_ch" + mcuTrack) || ctrl.id.contains("btn_" + mcuTrack))) {
                            boolean wasLit = (ctrl.value > 0);
                            ctrl.value = isMuted ? 0 : 127;
                            ctrl.isMuted = isMuted;
                            boolean isLit = (ctrl.value > 0);
                            if (wasLit != isLit) {
                                animateButtonTrigger(ctrl, isLit);
                            }
                            changed = true;
                        }
                    }
                }
            }

            for (ControlModel ctrl : allCtrls) {
                if (ctrl.midiChannel == channel) {
                    if ("button".equals(ctrl.type)) {
                        if (ctrl.midiNumber == noteNumber) {
                            int onVal = (ctrl.maxValue > 0) ? ctrl.maxValue : 127;
                            int offVal = (ctrl.minValue >= 0) ? ctrl.minValue : 0;
                            boolean wasLit = (ctrl.value > offVal);
                            boolean isLit = isNoteOn;
                            ctrl.value = isLit ? onVal : offVal;
                            ctrl.isMuted = !isLit;
                            syncFaderMuteFromButton(ctrl);
                            if (wasLit != isLit) {
                                animateButtonTrigger(ctrl, isLit);
                            }
                            changed = true;
                        }
                    }

                    if (ctrl.hasBottomButton && ctrl.buttonMidiNumber == noteNumber) {
                        boolean wasVal = ctrl.buttonValue;
                        ctrl.buttonValue = isNoteOn;
                        ctrl.isMuted = !isNoteOn;
                        if (wasVal != ctrl.buttonValue) {
                            animateButtonTrigger(ctrl, ctrl.buttonValue);
                        }
                        changed = true;
                    }
                }
            }
        }

        if (changed) {
            flashMidiLed();
            invalidate();
            scheduleStateSave();
        }
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        calculateScaleAndOffsets(w, h);
    }

    private void calculateScaleAndOffsets(int viewW, int viewH) {
        if (viewW <= 0 || viewH <= 0) return;

        boolean isPortrait = (viewH > viewW);
        float barSize = dp(56);

        if (isPortrait) {
            boolean isTop = "top".equalsIgnoreCase(sidebarPortraitPos);
            float barTop = isTop ? 0 : (viewH - barSize);
            float barBottom = isTop ? barSize : viewH;
            float barCenterY = barTop + barSize / 2.0f;

            sidebarRect.set(0, barTop, viewW, barBottom);

            // 1. Settings Button (Left)
            float sRadius = dp(18);
            settingsButtonRect.set(dp(14), barCenterY - sRadius, dp(14) + sRadius * 2, barCenterY + sRadius);

            // 2. Tabs Button (Next to Settings)
            float tW = dp(44);
            float tH = dp(38);
            tabsButtonRect.set(dp(62), barCenterY - tH / 2.0f, dp(62) + tW, barCenterY + tH / 2.0f);

            // 3. Battery Indicator (Right)
            batteryRect.set(viewW - dp(74), barCenterY - dp(18), viewW - dp(12), barCenterY + dp(18));

            availableW = viewW;
            availableH = viewH - barSize;
            canvasOriginX = 0f;
            canvasOriginY = isTop ? barSize : 0f;
        } else {
            boolean isLeft = "left".equalsIgnoreCase(sidebarLandscapePos);
            float barLeft = isLeft ? 0 : (viewW - barSize);
            float barRight = isLeft ? barSize : viewW;

            sidebarRect.set(barLeft, 0, barRight, viewH);

            float btnLeft = isLeft ? dp(6) : (viewW - dp(50));
            float btnRight = isLeft ? dp(50) : (viewW - dp(6));

            // Sidebar Buttons & Indicators (Top to bottom)
            settingsButtonRect.set(btnLeft, dp(10), btnRight, dp(54));
            tabsButtonRect.set(btnLeft, dp(62), btnRight, dp(106));
            batteryRect.set(btnLeft, viewH - dp(56), btnRight, viewH - dp(10));

            availableW = viewW - barSize;
            availableH = viewH;
            canvasOriginX = isLeft ? barSize : 0f;
            canvasOriginY = 0f;
        }

        boolean hasMultipleTabs = (layout != null && layout.pages != null && layout.pages.size() > 1);

        float baseW = (layout != null && layout.canvasWidth > 0) ? layout.canvasWidth : 920.0f;
        float baseH = (layout != null && layout.canvasHeight > 0) ? layout.canvasHeight : 460.0f;

        float scaleX = availableW / baseW;
        float scaleY = availableH / baseH;
        scale = Math.min(scaleX, scaleY);

        float canvasW = baseW * scale;
        float canvasH = baseH * scale;

        offsetX = canvasOriginX + (availableW - canvasW) / 2.0f;
        offsetY = canvasOriginY + (availableH - canvasH) / 2.0f;

        if (hasMultipleTabs) {
            float barW = Math.max(dp(70), layout.pages.size() * dp(16) + dp(8));
            float barH = dp(3.5f);
            float barX = canvasOriginX + (availableW - barW) / 2.0f;
            float barY = canvasOriginY + availableH - dp(5.5f); // Positioned at bottom of playable controls area
            bottomTabBarRect.set(barX, barY, barX + barW, barY + barH);
        } else {
            bottomTabBarRect.setEmpty();
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (layout == null || layout.pages == null || layout.pages.isEmpty()) return;

        float baseW = (layout.canvasWidth > 0) ? layout.canvasWidth : 920.0f;
        boolean hasMultipleTabs = (layout.pages.size() > 1);

        // 1. Draw Controls on scaled & centered canvas with clipping to prevent bar bleed
        canvas.save();
        canvas.clipRect(canvasOriginX, canvasOriginY, canvasOriginX + availableW, canvasOriginY + availableH);
        canvas.translate(offsetX, offsetY);

        float shiftPixels = dragInBaseUnits * scale;
        float baseWPixels = baseW * scale;

        if (isTransitioning) {
            int dir = (transitionToIndex > transitionFromIndex) ? 1 : -1;

            if (transitionFromBitmap != null && !transitionFromBitmap.isRecycled()) {
                canvas.drawBitmap(transitionFromBitmap, shiftPixels, 0, null);
            } else {
                PageModel fromPage = (transitionFromIndex >= 0 && transitionFromIndex < layout.pages.size())
                        ? layout.pages.get(transitionFromIndex) : null;
                if (fromPage != null) {
                    canvas.save();
                    canvas.translate(shiftPixels, 0);
                    canvas.scale(scale, scale);
                    drawControlsList(canvas, fromPage.controls);
                    canvas.restore();
                }
            }

            if (transitionToBitmap != null && !transitionToBitmap.isRecycled()) {
                canvas.drawBitmap(transitionToBitmap, shiftPixels + (dir * baseWPixels), 0, null);
            } else {
                PageModel toPage = (transitionToIndex >= 0 && transitionToIndex < layout.pages.size())
                        ? layout.pages.get(transitionToIndex) : null;
                if (toPage != null) {
                    canvas.save();
                    canvas.translate(shiftPixels + (dir * baseWPixels), 0);
                    canvas.scale(scale, scale);
                    drawControlsList(canvas, toPage.controls);
                    canvas.restore();
                }
            }
        } else if (isDraggingPage && Math.abs(dragInBaseUnits) > 0.01f) {
            int dir = (dragInBaseUnits < 0) ? 1 : -1;

            if (transitionFromBitmap != null && !transitionFromBitmap.isRecycled()) {
                canvas.drawBitmap(transitionFromBitmap, shiftPixels, 0, null);
            } else {
                canvas.save();
                canvas.translate(shiftPixels, 0);
                canvas.scale(scale, scale);
                drawControlsList(canvas, layout.getActivePage().controls);
                canvas.restore();
            }

            int targetIdx = (dragInBaseUnits < 0) ? layout.activePageIndex + 1 : layout.activePageIndex - 1;
            if (targetIdx >= 0 && targetIdx < layout.pages.size()) {
                if (transitionToBitmap != null && !transitionToBitmap.isRecycled()) {
                    canvas.drawBitmap(transitionToBitmap, shiftPixels + (dir * baseWPixels), 0, null);
                } else {
                    canvas.save();
                    canvas.translate(shiftPixels + (dir * baseWPixels), 0);
                    canvas.scale(scale, scale);
                    drawControlsList(canvas, layout.pages.get(targetIdx).controls);
                    canvas.restore();
                }
            }
        } else {
            canvas.scale(scale, scale);
            drawControlsList(canvas, layout.controls);
        }

        canvas.restore();

        // 2. Draw Bottom Tab Bar Indicator (if multiple pages, ultra-sleek at the very bottom edge)
        if (hasMultipleTabs) {
            drawBottomTabBar(canvas);
        }

        // 3. Draw Vertical Sidebar (Settings at top, Tabs button, Battery indicator at bottom)
        drawVerticalSidebar(canvas);

        // 4. Draw Tab Flyout Modal if open
        if (isTabFlyoutOpen) {
            drawTabFlyout(canvas);
        }
    }

    private void drawControlsList(Canvas canvas, List<ControlModel> list) {
        if (list == null) return;
        for (ControlModel ctrl : list) {
            if ("fader".equals(ctrl.type)) {
                drawFader(canvas, ctrl);
            } else if ("knob".equals(ctrl.type)) {
                drawKnob(canvas, ctrl);
            } else if ("button".equals(ctrl.type)) {
                drawButton(canvas, ctrl);
            } else if ("xypad".equals(ctrl.type)) {
                drawXYPad(canvas, ctrl);
            } else if ("label".equals(ctrl.type)) {
                drawLabel(canvas, ctrl);
            } else if ("vu".equals(ctrl.type)) {
                drawVuMeter(canvas, ctrl);
            }
        }
    }

    // -----------------------------------------------------------------
    // Page Tab Navigation & Zero-Allocation 120 FPS Slide Transition
    // -----------------------------------------------------------------
    private Bitmap createPageBitmap(PageModel page) {
        if (page == null) return null;
        float baseW = (layout != null && layout.canvasWidth > 0) ? layout.canvasWidth : 920.0f;
        float baseH = (layout != null && layout.canvasHeight > 0) ? layout.canvasHeight : 460.0f;
        int bW = Math.max(1, Math.round(baseW * scale));
        int bH = Math.max(1, Math.round(baseH * scale));
        try {
            Bitmap bmp = Bitmap.createBitmap(bW, bH, Bitmap.Config.ARGB_8888);
            Canvas c = new Canvas(bmp);
            c.scale(scale, scale);
            drawControlsList(c, page.controls);
            return bmp;
        } catch (Throwable t) {
            return null;
        }
    }

    private void recycleTransitionBitmaps() {
        if (transitionFromBitmap != null) {
            transitionFromBitmap.recycle();
            transitionFromBitmap = null;
        }
        if (transitionToBitmap != null) {
            transitionToBitmap.recycle();
            transitionToBitmap = null;
        }
        cachedFromIndex = -1;
        cachedToIndex = -1;
    }

    private void drawBottomTabBar(Canvas canvas) {
        if (layout == null || layout.pages == null || layout.pages.size() <= 1) return;
        int numPages = layout.pages.size();
        if (bottomTabBarRect.isEmpty()) return;

        // Subtle dark glass track at the absolute bottom
        paintFill.setStyle(Paint.Style.FILL);
        paintFill.setColor(isBottomSwipeActive ? Color.parseColor("#44333338") : Color.parseColor("#22222226"));
        canvas.drawRoundRect(bottomTabBarRect, dp(1.8f), dp(1.8f), paintFill);

        // Continuous active indicator position
        float baseW = (layout.canvasWidth > 0) ? layout.canvasWidth : 920.0f;
        float activeFloatIndex;
        if (isTransitioning) {
            int dir = (transitionToIndex > transitionFromIndex) ? 1 : -1;
            float progress = Math.abs(dragInBaseUnits) / baseW;
            activeFloatIndex = transitionFromIndex + dir * progress;
        } else if (isDraggingPage) {
            activeFloatIndex = layout.activePageIndex - (dragInBaseUnits / baseW);
        } else {
            activeFloatIndex = layout.activePageIndex;
        }
        activeFloatIndex = Math.max(0f, Math.min(numPages - 1, activeFloatIndex));

        float totalDotsW = (numPages - 1) * dp(16);
        float startX = bottomTabBarRect.centerX() - (totalDotsW / 2.0f);
        float cy = bottomTabBarRect.centerY();

        // Subtle Inactive Page Ticks
        paintFill.setStyle(Paint.Style.FILL);
        paintFill.setColor(Color.parseColor("#44FFFFFF"));
        for (int i = 0; i < numPages; i++) {
            float dx = startX + i * dp(16);
            canvas.drawCircle(dx, cy, dp(1.0f), paintFill);
        }

        // Active Apple-Style Glowing Pill Line
        float activeX = startX + activeFloatIndex * dp(16);
        float pillW = dp(16);
        float pillH = dp(3.2f);
        RectF activePill = new RectF(activeX - pillW / 2.0f, cy - pillH / 2.0f, activeX + pillW / 2.0f, cy + pillH / 2.0f);

        // Neon Blue Bloom
        paintFill.setColor(isBottomSwipeActive ? Color.parseColor("#8840C4FF") : Color.parseColor("#440A84FF"));
        canvas.drawRoundRect(new RectF(activePill.left - dp(1.5f), activePill.top - dp(0.8f), activePill.right + dp(1.5f), activePill.bottom + dp(0.8f)), dp(2), dp(2), paintFill);

        // Core Pill
        paintFill.setColor(isBottomSwipeActive ? Color.parseColor("#40C4FF") : Color.parseColor("#0A84FF"));
        canvas.drawRoundRect(activePill, dp(1.6f), dp(1.6f), paintFill);
    }

    public void animateToPage(int targetIndex) {
        if (layout == null || layout.pages == null || targetIndex < 0 || targetIndex >= layout.pages.size()) return;
        if (targetIndex == layout.activePageIndex && !isDraggingPage) return;

        if (pageAnimator != null && pageAnimator.isRunning()) {
            pageAnimator.cancel();
        }

        final int fromIdx = layout.activePageIndex;
        final int toIdx = targetIndex;
        final int dir = (toIdx > fromIdx) ? 1 : -1;
        final float baseW = (layout.canvasWidth > 0) ? layout.canvasWidth : 920.0f;

        transitionFromIndex = fromIdx;
        transitionToIndex = toIdx;
        isTransitioning = true;

        // Prepare zero-overhead GPU bitmaps
        if (cachedFromIndex != fromIdx || transitionFromBitmap == null) {
            if (transitionFromBitmap != null) transitionFromBitmap.recycle();
            transitionFromBitmap = createPageBitmap(layout.pages.get(fromIdx));
            cachedFromIndex = fromIdx;
        }
        if (cachedToIndex != toIdx || transitionToBitmap == null) {
            if (transitionToBitmap != null) transitionToBitmap.recycle();
            transitionToBitmap = createPageBitmap(layout.pages.get(toIdx));
            cachedToIndex = toIdx;
        }

        float startVal = dragInBaseUnits;
        float endVal = -dir * baseW;
        float distRatio = Math.abs(endVal - startVal) / baseW;
        long duration = Math.max(200, Math.round(310 * Math.min(1.0f, Math.max(0.50f, distRatio))));

        pageAnimator = ValueAnimator.ofFloat(startVal, endVal);
        pageAnimator.setDuration(duration);
        pageAnimator.setInterpolator(fluidEaseInterpolator);
        pageAnimator.addUpdateListener(animation -> {
            dragInBaseUnits = (Float) animation.getAnimatedValue();
            invalidate();
        });
        pageAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                isTransitioning = false;
                dragInBaseUnits = 0f;
                layout.setActivePageIndex(toIdx);
                activeTouches.clear();
                recycleTransitionBitmaps();
                performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                invalidate();
                scheduleStateSave();
            }

            @Override
            public void onAnimationCancel(Animator animation) {
                isTransitioning = false;
                dragInBaseUnits = 0f;
                recycleTransitionBitmaps();
            }
        });
        pageAnimator.start();
    }

    private void animateBackToCurrentPage() {
        if (pageAnimator != null && pageAnimator.isRunning()) {
            pageAnimator.cancel();
        }

        pageAnimator = ValueAnimator.ofFloat(dragInBaseUnits, 0f);
        pageAnimator.setDuration(220);
        pageAnimator.setInterpolator(snapBackInterpolator);
        pageAnimator.addUpdateListener(animation -> {
            dragInBaseUnits = (Float) animation.getAnimatedValue();
            invalidate();
        });
        pageAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                dragInBaseUnits = 0f;
                isDraggingPage = false;
                recycleTransitionBitmaps();
                invalidate();
            }

            @Override
            public void onAnimationCancel(Animator animation) {
                dragInBaseUnits = 0f;
                isDraggingPage = false;
                recycleTransitionBitmaps();
            }
        });
        pageAnimator.start();
    }

    // System Bar: Right Vertical Sidebar in Landscape; Bottom Horizontal Bar in Portrait
    private void drawVerticalSidebar(Canvas canvas) {
        boolean isPortrait = (getHeight() > getWidth());

        // Pure black 100% OLED background
        paintFill.setShader(null);
        paintFill.setColor(Color.BLACK);
        canvas.drawRect(sidebarRect, paintFill);

        paintStroke.setColor(Color.parseColor("#26FFFFFF"));
        paintStroke.setStrokeWidth(dp(1));
        if (isPortrait) {
            boolean isTop = "top".equalsIgnoreCase(sidebarPortraitPos);
            float lineY = isTop ? sidebarRect.bottom : sidebarRect.top;
            canvas.drawLine(0, lineY, getWidth(), lineY, paintStroke);
        } else {
            boolean isLeft = "left".equalsIgnoreCase(sidebarLandscapePos);
            float lineX = isLeft ? sidebarRect.right : sidebarRect.left;
            canvas.drawLine(lineX, 0, lineX, getHeight(), paintStroke);
        }

        // 1. Settings Button
        float scx = settingsButtonRect.centerX();
        float scy = settingsButtonRect.centerY();
        float sRadius = dp(18);

        paintFill.setColor(Color.parseColor("#441C1C1E"));
        canvas.drawCircle(scx, scy, sRadius, paintFill);
        paintStroke.setColor(Color.parseColor("#552C2C2E"));
        paintStroke.setStrokeWidth(dp(1));
        canvas.drawCircle(scx, scy, sRadius, paintStroke);

        // Connection LED Dot
        int ledColor;
        if (isConnected) {
            ledColor = isMidiActive ? Color.parseColor("#00E5FF") : Color.parseColor("#30D158");
        } else if (isConnecting) {
            ledColor = Color.parseColor("#FF9F0A");
        } else {
            ledColor = Color.parseColor("#8E8E93");
        }
        paintFill.setColor(ledColor);
        canvas.drawCircle(scx - dp(6), scy, dp(3.2f), paintFill);

        // Sliders Glyph
        paintStroke.setColor(Color.parseColor("#E5E5EA"));
        paintStroke.setStrokeWidth(dp(1.8f));
        paintStroke.setStrokeCap(Paint.Cap.ROUND);
        float lineX = scx + dp(3);
        canvas.drawLine(lineX, scy - dp(4), lineX + dp(7), scy - dp(4), paintStroke);
        canvas.drawLine(lineX - dp(2), scy, lineX + dp(5), scy, paintStroke);
        canvas.drawLine(lineX, scy + dp(4), lineX + dp(7), scy + dp(4), paintStroke);

        // 2. Tabs Button
        float tcx = tabsButtonRect.centerX();
        float tcy = tabsButtonRect.centerY();

        boolean hasMultipleTabs = (layout != null && layout.pages != null && layout.pages.size() > 1);
        paintFill.setColor(isTabFlyoutOpen ? Color.parseColor("#330A84FF") : Color.parseColor("#441C1C1E"));
        canvas.drawRoundRect(tabsButtonRect, dp(12), dp(12), paintFill);
        paintStroke.setColor(isTabFlyoutOpen ? Color.parseColor("#0A84FF") : Color.parseColor("#552C2C2E"));
        paintStroke.setStrokeWidth(dp(1));
        canvas.drawRoundRect(tabsButtonRect, dp(12), dp(12), paintStroke);

        // Stacked Rectangles / Layers Glyph
        paintStroke.setColor(hasMultipleTabs ? Color.parseColor("#E5E5EA") : Color.parseColor("#8E8E93"));
        paintStroke.setStrokeWidth(dp(1.5f));
        paintStroke.setStyle(Paint.Style.STROKE);
        RectF r1 = new RectF(tcx - dp(8), tcy - dp(9), tcx + dp(4), tcy + dp(3));
        canvas.drawRoundRect(r1, dp(2), dp(2), paintStroke);
        RectF r2 = new RectF(tcx - dp(4), tcy - dp(5), tcx + dp(8), tcy + dp(7));
        canvas.drawRoundRect(r2, dp(2), dp(2), paintStroke);

        // Current page badge text
        int pageIndex = (layout != null) ? layout.activePageIndex + 1 : 1;
        paintText.setTextSize(dp(8.5f));
        paintText.setColor(hasMultipleTabs ? Color.parseColor("#0A84FF") : Color.parseColor("#8E8E93"));
        canvas.drawText("P" + pageIndex, tcx, tabsButtonRect.bottom - dp(4), paintText);

        // 3. Battery Indicator
        float batW = dp(22);
        float batH = dp(11);
        float bcx = batteryRect.centerX();
        float bcy = batteryRect.centerY();

        RectF bShell;
        if (isPortrait) {
            // In portrait mode: side-by-side percentage and battery shell
            float shellCenterX = bcx + dp(13);
            float textX = bcx - dp(13);

            paintText.setTextSize(dp(10.5f));
            paintText.setColor(Color.parseColor("#E5E5EA"));
            Paint.FontMetrics fm = paintText.getFontMetrics();
            float textY = bcy - (fm.ascent + fm.descent) / 2.0f;
            canvas.drawText(batteryPercent + "%", textX, textY, paintText);

            bShell = new RectF(shellCenterX - batW / 2.0f, bcy - batH / 2.0f, shellCenterX + batW / 2.0f, bcy + batH / 2.0f);
        } else {
            // In landscape mode: stacked vertically
            bcy = batteryRect.centerY() + dp(4);
            bShell = new RectF(bcx - batW / 2.0f, bcy - batH / 2.0f, bcx + batW / 2.0f, bcy + batH / 2.0f);

            paintText.setTextSize(dp(9.5f));
            paintText.setColor(Color.parseColor("#E5E5EA"));
            canvas.drawText(batteryPercent + "%", bcx, batteryRect.top + dp(8), paintText);
        }

        // Battery outer shell
        paintStroke.setColor(Color.parseColor("#8E8E93"));
        paintStroke.setStrokeWidth(dp(1.2f));
        paintStroke.setStyle(Paint.Style.STROKE);
        canvas.drawRoundRect(bShell, dp(3), dp(3), paintStroke);

        // Battery tip
        RectF bTip = new RectF(bShell.right + dp(1), bcy - dp(2.5f), bShell.right + dp(2.5f), bcy + dp(2.5f));
        paintFill.setStyle(Paint.Style.FILL);
        paintFill.setColor(Color.parseColor("#8E8E93"));
        canvas.drawRoundRect(bTip, dp(1), dp(1), paintFill);

        // Battery level fill
        float pct = Math.max(0.05f, Math.min(1.0f, batteryPercent / 100.0f));
        float fillW = (bShell.width() - dp(4)) * pct;
        RectF bFill = new RectF(bShell.left + dp(2), bShell.top + dp(2), bShell.left + dp(2) + fillW, bShell.bottom - dp(2));

        int batColor;
        if (isBatteryCharging) {
            batColor = Color.parseColor("#30D158");
        } else if (batteryPercent <= 10) {
            batColor = Color.parseColor("#FF453A");
        } else if (batteryPercent <= 20) {
            batColor = Color.parseColor("#FF9F0A");
        } else {
            batColor = Color.parseColor("#30D158");
        }
        paintFill.setColor(batColor);
        canvas.drawRoundRect(bFill, dp(1.5f), dp(1.5f), paintFill);
    }

    // Floating Flyout Card for Tabs Selection (Opens smoothly without covering controls permanently)
    private void drawTabFlyout(Canvas canvas) {
        if (layout == null || layout.pages == null || layout.pages.isEmpty()) return;

        boolean isPortrait = (getHeight() > getWidth());
        int count = layout.pages.size();
        float itemH = dp(38);
        float cardW = dp(160);
        float cardH = count * itemH + dp(16);

        if (isPortrait) {
            boolean isTop = "top".equalsIgnoreCase(sidebarPortraitPos);
            float cardTop;
            float cardBottom;
            if (isTop) {
                cardTop = sidebarRect.bottom + dp(8);
                cardBottom = Math.min(getHeight() - dp(10), cardTop + cardH);
            } else {
                cardBottom = sidebarRect.top - dp(8);
                cardTop = Math.max(dp(10), cardBottom - cardH);
            }
            float cardLeft = Math.max(dp(12), Math.min(tabsButtonRect.left, getWidth() - cardW - dp(12)));
            float cardRight = cardLeft + cardW;
            flyoutCardRect.set(cardLeft, cardTop, cardRight, cardBottom);
        } else {
            boolean isLeft = "left".equalsIgnoreCase(sidebarLandscapePos);
            float cardTop = Math.min(tabsButtonRect.top, getHeight() - cardH - dp(10));
            float cardLeft;
            float cardRight;
            if (isLeft) {
                cardLeft = sidebarRect.right + dp(8);
                cardRight = cardLeft + cardW;
            } else {
                cardRight = sidebarRect.left - dp(8);
                cardLeft = cardRight - cardW;
            }
            flyoutCardRect.set(cardLeft, cardTop, cardRight, cardTop + cardH);
        }

        // Card Drop Shadow / Glow
        paintFill.setColor(Color.parseColor("#F51C1C1E"));
        canvas.drawRoundRect(flyoutCardRect, dp(14), dp(14), paintFill);
        paintStroke.setColor(Color.parseColor("#553A3A3C"));
        paintStroke.setStrokeWidth(dp(1.2f));
        canvas.drawRoundRect(flyoutCardRect, dp(14), dp(14), paintStroke);

        tabFlyoutItemRects.clear();
        float curY = flyoutCardRect.top + dp(8);

        paintText.setTextSize(dp(12.5f));
        paintText.setTextAlign(Paint.Align.LEFT);

        for (int i = 0; i < count; i++) {
            RectF itemRect = new RectF(flyoutCardRect.left + dp(8), curY, flyoutCardRect.right - dp(8), curY + itemH);
            tabFlyoutItemRects.add(new RectF(itemRect));

            boolean isActive = (i == layout.activePageIndex);
            if (isActive) {
                paintFill.setColor(Color.parseColor("#330A84FF"));
                canvas.drawRoundRect(itemRect, dp(10), dp(10), paintFill);
                paintStroke.setColor(Color.parseColor("#0A84FF"));
                paintStroke.setStrokeWidth(dp(1.2f));
                canvas.drawRoundRect(itemRect, dp(10), dp(10), paintStroke);

                paintText.setColor(Color.WHITE);
            } else {
                paintText.setColor(Color.parseColor("#8E8E93"));
            }

            String name = layout.pages.get(i).name != null ? layout.pages.get(i).name : ("Screen " + (i + 1));
            Paint.FontMetrics fm = paintText.getFontMetrics();
            float baseline = itemRect.centerY() - (fm.ascent + fm.descent) / 2.0f;
            canvas.drawText(name, itemRect.left + dp(12), baseline, paintText);

            if (isActive) {
                paintText.setTextAlign(Paint.Align.RIGHT);
                canvas.drawText("✓", itemRect.right - dp(12), baseline, paintText);
                paintText.setTextAlign(Paint.Align.LEFT);
            }

            curY += itemH;
        }

        paintText.setTextAlign(Paint.Align.CENTER);
    }

    // -----------------------------------------------------------------
    // Controls 2D Hardware-grade Neon Glowing Drawing
    // -----------------------------------------------------------------

    private int adjustAlpha(int color, float factor) {
        int alpha = Math.max(0, Math.min(255, Math.round(Color.alpha(color) * factor)));
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
    }

    private int blendColors(int c1, int c2, float ratio) {
        float r = Math.max(0.0f, Math.min(1.0f, ratio));
        float ir = 1.0f - r;
        int a = Math.round(Color.alpha(c1) * ir + Color.alpha(c2) * r);
        int red = Math.round(Color.red(c1) * ir + Color.red(c2) * r);
        int green = Math.round(Color.green(c1) * ir + Color.green(c2) * r);
        int blue = Math.round(Color.blue(c1) * ir + Color.blue(c2) * r);
        return Color.argb(a, red, green, blue);
    }

    private int deriveDarkBaseColor(int accentColor) {
        float[] hsv = new float[3];
        Color.colorToHSV(accentColor, hsv);
        hsv[1] = Math.min(1.0f, Math.max(0.65f, hsv[1] * 1.15f));
        hsv[2] = Math.max(0.12f, Math.min(0.42f, hsv[2] * 0.38f));
        return Color.HSVToColor(hsv);
    }

    private void setFaderPressed(ControlModel ctrl, boolean pressed) {
        if (ctrl == null) return;
        if (ctrl.isFaderPressed == pressed) return;
        ctrl.isFaderPressed = pressed;

        if (ctrl.faderThumbAnimator != null && ctrl.faderThumbAnimator.isRunning()) {
            ctrl.faderThumbAnimator.cancel();
        }

        final float startScale = (ctrl.faderThumbScale > 0.5f) ? ctrl.faderThumbScale : 1.0f;
        final float targetScale = pressed ? 1.15f : 1.0f;

        ctrl.faderThumbAnimator = ValueAnimator.ofFloat(startScale, targetScale);
        ctrl.faderThumbAnimator.setDuration(pressed ? 130 : 200);
        ctrl.faderThumbAnimator.setInterpolator(pressed ? new DecelerateInterpolator(1.8f) : new OvershootInterpolator(1.3f));
        ctrl.faderThumbAnimator.addUpdateListener(anim -> {
            ctrl.faderThumbScale = (Float) anim.getAnimatedValue();
            invalidate();
        });
        ctrl.faderThumbAnimator.start();
    }

    private void animateButtonTrigger(ControlModel ctrl, boolean isNowActive) {
        if (ctrl == null) return;
        if (ctrl.buttonAnimator != null && ctrl.buttonAnimator.isRunning()) {
            ctrl.buttonAnimator.cancel();
        }

        final float startActivation = (ctrl.animatedActivation >= 0f) ? ctrl.animatedActivation : (isNowActive ? 0.0f : 1.0f);
        final float targetActivation = isNowActive ? 1.0f : 0.0f;

        ctrl.buttonAnimator = ValueAnimator.ofFloat(0.0f, 1.0f);
        ctrl.buttonAnimator.setDuration(280);
        ctrl.buttonAnimator.addUpdateListener(anim -> {
            float p = (Float) anim.getAnimatedValue();

            // 1. Activation level (smooth color crossfade)
            ctrl.animatedActivation = startActivation + (targetActivation - startActivation) * p;

            // 2. Motion graphics physical scale spring bounce
            if (isNowActive) {
                if (p < 0.18f) {
                    // Quick tactile compression inward
                    float t = p / 0.18f;
                    ctrl.buttonScale = 1.0f - (0.07f * t); // 1.0 -> 0.93
                } else if (p < 0.55f) {
                    // Elastic spring pop overshoot!
                    float t = (p - 0.18f) / 0.37f;
                    ctrl.buttonScale = 0.93f + (0.14f * (float) Math.sin(t * Math.PI / 2.0)); // 0.93 -> 1.07
                } else {
                    // Settle gently back to 1.0
                    float t = (p - 0.55f) / 0.45f;
                    ctrl.buttonScale = 1.07f - (0.07f * t); // 1.07 -> 1.00
                }
            } else {
                // Deactivation compression and smooth rebound
                if (p < 0.22f) {
                    float t = p / 0.22f;
                    ctrl.buttonScale = 1.0f - (0.06f * t); // 1.0 -> 0.94
                } else {
                    float t = (p - 0.22f) / 0.78f;
                    ctrl.buttonScale = 0.94f + (0.06f * t); // 0.94 -> 1.00
                }
            }

            // 3. Expanding Shockwave pulse ring
            ctrl.buttonGlowProgress = p;
            ctrl.buttonGlowAlpha = (float) Math.sin(p * Math.PI) * (isNowActive ? 0.90f : 0.50f);

            // 4. Specular Flash Burst
            if (isNowActive) {
                ctrl.buttonFlash = Math.max(0.0f, 1.0f - p * 3.2f);
            } else {
                ctrl.buttonFlash = 0.0f;
            }

            invalidate();
        });
        ctrl.buttonAnimator.addListener(new AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(Animator animation) {
                ctrl.animatedActivation = targetActivation;
                ctrl.buttonScale = 1.0f;
                ctrl.buttonGlowProgress = 0.0f;
                ctrl.buttonGlowAlpha = 0.0f;
                ctrl.buttonFlash = 0.0f;
                invalidate();
            }
        });
        ctrl.buttonAnimator.start();
    }

    private void drawGlowingLine(Canvas canvas, float x1, float y1, float x2, float y2, int color, float strokeWidth) {
        paintStroke.setStrokeCap(Paint.Cap.ROUND);
        // Outer diffuse bloom
        paintStroke.setStrokeWidth(strokeWidth * 3.5f);
        paintStroke.setColor(adjustAlpha(color, 0.22f));
        canvas.drawLine(x1, y1, x2, y2, paintStroke);

        // Medium bloom
        paintStroke.setStrokeWidth(strokeWidth * 2.0f);
        paintStroke.setColor(adjustAlpha(color, 0.50f));
        canvas.drawLine(x1, y1, x2, y2, paintStroke);

        // Solid neon body
        paintStroke.setStrokeWidth(strokeWidth);
        paintStroke.setColor(color);
        canvas.drawLine(x1, y1, x2, y2, paintStroke);

        // Hot center core
        paintStroke.setStrokeWidth(strokeWidth * 0.45f);
        paintStroke.setColor(Color.WHITE);
        canvas.drawLine(x1, y1, x2, y2, paintStroke);
    }

    private void drawGlowingRoundRect(Canvas canvas, RectF r, float rx, float ry, int color, float strokeWidth) {
        paintStroke.setStrokeCap(Paint.Cap.ROUND);
        // Wide bloom
        paintStroke.setStrokeWidth(strokeWidth + 8.0f);
        paintStroke.setColor(adjustAlpha(color, 0.16f));
        canvas.drawRoundRect(r, rx, ry, paintStroke);

        // Medium bloom
        paintStroke.setStrokeWidth(strokeWidth + 3.0f);
        paintStroke.setColor(adjustAlpha(color, 0.42f));
        canvas.drawRoundRect(r, rx, ry, paintStroke);

        // Sharp neon rim
        paintStroke.setStrokeWidth(strokeWidth);
        paintStroke.setColor(color);
        canvas.drawRoundRect(r, rx, ry, paintStroke);
    }

    private void drawGlowingCircle(Canvas canvas, float cx, float cy, float radius, int color, float strokeWidth) {
        paintStroke.setStrokeCap(Paint.Cap.ROUND);
        // Wide bloom
        paintStroke.setStrokeWidth(strokeWidth + 8.0f);
        paintStroke.setColor(adjustAlpha(color, 0.16f));
        canvas.drawCircle(cx, cy, radius, paintStroke);

        // Medium bloom
        paintStroke.setStrokeWidth(strokeWidth + 3.0f);
        paintStroke.setColor(adjustAlpha(color, 0.42f));
        canvas.drawCircle(cx, cy, radius, paintStroke);

        // Sharp rim
        paintStroke.setStrokeWidth(strokeWidth);
        paintStroke.setColor(color);
        canvas.drawCircle(cx, cy, radius, paintStroke);
    }

    private void drawGlowingArc(Canvas canvas, RectF arcRect, float startAngle, float sweepAngle, int color, float strokeWidth) {
        paintStroke.setStrokeCap(Paint.Cap.ROUND);
        // Wide bloom
        paintStroke.setStrokeWidth(strokeWidth + 8.0f);
        paintStroke.setColor(adjustAlpha(color, 0.18f));
        canvas.drawArc(arcRect, startAngle, sweepAngle, false, paintStroke);

        // Medium bloom
        paintStroke.setStrokeWidth(strokeWidth + 3.0f);
        paintStroke.setColor(adjustAlpha(color, 0.45f));
        canvas.drawArc(arcRect, startAngle, sweepAngle, false, paintStroke);

        // Core neon arc
        paintStroke.setStrokeWidth(strokeWidth);
        paintStroke.setColor(color);
        canvas.drawArc(arcRect, startAngle, sweepAngle, false, paintStroke);

        // Hot center highlight
        paintStroke.setStrokeWidth(strokeWidth * 0.45f);
        paintStroke.setColor(Color.WHITE);
        canvas.drawArc(arcRect, startAngle, sweepAngle, false, paintStroke);
    }

    private void drawFader(Canvas canvas, ControlModel ctrl) {
        boolean isHorizontal = "horizontal".equalsIgnoreCase(ctrl.orientation);
        float pillH = 26.0f;
        boolean hasLabel = ctrl.hasLabel;
        boolean isBottom = "bottom".equalsIgnoreCase(ctrl.labelPosition);

        RectF trackRect;
        RectF pillRect = null;

        if (isHorizontal) {
            if (hasLabel) {
                if (isBottom) {
                    pillRect = new RectF(ctrl.x, ctrl.y + ctrl.height - pillH, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
                    trackRect = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + ctrl.height - pillH - 4.0f);
                } else {
                    pillRect = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + pillH);
                    trackRect = new RectF(ctrl.x, ctrl.y + pillH + 4.0f, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
                }
            } else {
                trackRect = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
            }
        } else {
            if (hasLabel) {
                if (isBottom) {
                    pillRect = new RectF(ctrl.x, ctrl.y + ctrl.height - pillH, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
                    trackRect = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + ctrl.height - pillH - 8.0f);
                } else {
                    pillRect = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + pillH);
                    trackRect = new RectF(ctrl.x, ctrl.y + pillH + 8.0f, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
                }
            } else {
                trackRect = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
            }

            if (ctrl.hasBottomButton) {
                trackRect.bottom -= 56.0f;
            }
        }

        // 1. Draw Pill Label & Glowing Neon Line
        if (hasLabel && pillRect != null) {
            paintFill.setShader(null);
            paintFill.setColor(Color.parseColor("#0C0E12"));
            canvas.drawRoundRect(pillRect, 8.0f, 8.0f, paintFill);

            paintStroke.setColor(Color.parseColor("#262932"));
            paintStroke.setStrokeWidth(1.2f);
            canvas.drawRoundRect(pillRect, 8.0f, 8.0f, paintStroke);

            float fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 11.5f;
            paintText.setColor(Color.WHITE);
            paintText.setTextSize(fSize);
            paintText.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
            paintText.setLetterSpacing(0.04f);

            canvas.save();
            canvas.clipRect(pillRect.left + 2.0f, pillRect.top + 1.0f, pillRect.right - 2.0f, pillRect.bottom - 1.0f);
            Paint.FontMetrics fm = paintText.getFontMetrics();
            float textBaseY = pillRect.centerY() - (fm.ascent + fm.descent) / 2.0f;
            canvas.drawText(ctrl.label != null ? ctrl.label : "", pillRect.centerX(), textBaseY, paintText);
            canvas.restore();
            paintText.setLetterSpacing(0.0f);
        }

        float range = (ctrl.maxValue > ctrl.minValue) ? (ctrl.maxValue - ctrl.minValue) : 127.0f;
        float pct = (ctrl.value - ctrl.minValue) / range;
        pct = Math.max(0.0f, Math.min(1.0f, pct));
        String fStyle = (ctrl.faderStyle != null) ? ctrl.faderStyle.toLowerCase() : "standard";

        if (isHorizontal) {
            // Horizontal Fader Slot
            float slotH = 16.0f;
            float slotY = trackRect.centerY() - slotH / 2.0f;
            RectF slotRect = new RectF(trackRect.left + 4.0f, slotY, trackRect.right - 4.0f, slotY + slotH);

            // Scale graduation ticks above & below slot
            int numTicks = 9;
            float tickStep = slotRect.width() / (float)(numTicks - 1);
            paintStroke.setColor(Color.parseColor("#383C48"));
            paintStroke.setStrokeWidth(1.0f);
            for (int i = 0; i < numTicks; i++) {
                float tx = slotRect.left + i * tickStep;
                canvas.drawLine(tx, slotY - 8.0f, tx, slotY - 2.0f, paintStroke);
                canvas.drawLine(tx, slotRect.bottom + 2.0f, tx, slotRect.bottom + 8.0f, paintStroke);
            }

            // Deep recessed slot background
            paintFill.setShader(null);
            paintFill.setColor(Color.parseColor("#08090C"));
            canvas.drawRoundRect(slotRect, 6.0f, 6.0f, paintFill);
            paintStroke.setColor(Color.parseColor("#1C1E26"));
            paintStroke.setStrokeWidth(1.2f);
            canvas.drawRoundRect(slotRect, 6.0f, 6.0f, paintStroke);

            float travelW = slotRect.width() - 12.0f;
            float beamLeft = 0, beamRight = 0;
            float thumbW = 28.0f;
            float thumbH = Math.min(ctrl.height + 4.0f, 58.0f);
            float thumbX = 0;

            if ("inverted".equals(fStyle)) {
                float fillW = travelW * pct;
                beamRight = slotRect.right - 6.0f;
                beamLeft = beamRight - fillW;
                thumbX = (slotRect.right - 6.0f) - fillW - (thumbW / 2.0f);
            } else if ("centered".equals(fStyle)) {
                // Center notch tick
                paintStroke.setColor(Color.parseColor("#4F5466"));
                paintStroke.setStrokeWidth(2.0f);
                canvas.drawLine(slotRect.centerX(), slotY - 6.0f, slotRect.centerX(), slotRect.bottom + 6.0f, paintStroke);

                if (pct >= 0.5f) {
                    beamLeft = slotRect.centerX();
                    beamRight = beamLeft + (pct - 0.5f) * travelW;
                } else {
                    beamRight = slotRect.centerX();
                    beamLeft = beamRight - (0.5f - pct) * travelW;
                }
                thumbX = (slotRect.left + 6.0f) + pct * travelW - (thumbW / 2.0f);
            } else {
                float fillW = travelW * pct;
                beamLeft = slotRect.left + 6.0f;
                beamRight = beamLeft + fillW;
                thumbX = (slotRect.left + 6.0f) + fillW - (thumbW / 2.0f);
            }

            // Level & Glowing Neon Beam inside Slot
            if (Math.abs(beamRight - beamLeft) > 2.0f) {
                drawGlowingLine(canvas, beamLeft, slotRect.centerY(), beamRight, slotRect.centerY(), ctrl.accentColor, 3.5f);
            }

            // Machined Aluminum Slider Thumb (Horizontal mode: taller than wide)
            thumbX = Math.max(slotRect.left - 2.0f, Math.min(slotRect.right - thumbW + 2.0f, thumbX));
            float thumbY = trackRect.centerY() - thumbH / 2.0f;
            RectF thumbRect = new RectF(thumbX, thumbY, thumbX + thumbW, thumbY + thumbH);

            float tScale = (ctrl.faderThumbScale > 0.5f) ? ctrl.faderThumbScale : 1.0f;
            if (Math.abs(tScale - 1.0f) > 0.002f) {
                float tcx = thumbRect.centerX();
                float tcy = thumbRect.centerY();
                float halfW = (thumbW * tScale) / 2.0f;
                float halfH = (thumbH * tScale) / 2.0f;
                thumbRect.set(tcx - halfW, tcy - halfH, tcx + halfW, tcy + halfH);
            }

            float elevation = Math.max(0.0f, Math.min(1.0f, (tScale - 1.0f) / 0.15f));
            paintFill.setShader(null);
            paintFill.setColor(Color.argb(Math.round(150 + 65 * elevation), 0, 0, 0));
            canvas.drawRoundRect(new RectF(thumbRect.left - 1.5f * elevation, thumbRect.top + 3.0f + 2.0f * elevation, thumbRect.right + 1.5f * elevation, thumbRect.bottom + 4.0f + 3.0f * elevation), 5.5f, 5.5f, paintFill);

            LinearGradient metalGrad = new LinearGradient(
                thumbRect.left, thumbRect.top, thumbRect.right, thumbRect.top,
                new int[]{Color.parseColor("#444957"), Color.parseColor("#262832"), Color.parseColor("#1A1B21"), Color.parseColor("#101115")},
                new float[]{0.0f, 0.25f, 0.60f, 1.0f},
                Shader.TileMode.CLAMP
            );
            paintFill.setShader(metalGrad);
            canvas.drawRoundRect(thumbRect, 4.5f, 4.5f, paintFill);
            paintFill.setShader(null);

            paintStroke.setColor(Color.parseColor("#5A6072"));
            paintStroke.setStrokeWidth(1.0f);
            canvas.drawRoundRect(thumbRect, 4.5f, 4.5f, paintStroke);

            if (elevation > 0.05f) {
                drawGlowingRoundRect(canvas, thumbRect, 4.5f, 4.5f, ctrl.accentColor, 1.8f * elevation);
            }

            // Center Vertical Glowing Neon Slit
            float slitH = 16.0f * tScale;
            drawGlowingLine(canvas, thumbRect.centerX(), thumbRect.centerY() - slitH / 2.0f, thumbRect.centerX(), thumbRect.centerY() + slitH / 2.0f, ctrl.accentColor, 3.0f + 1.5f * elevation);
        } else {
            // Vertical Fader Slot (Groove / Recess)
            float slotW = 16.0f;
            float slotX = trackRect.centerX() - slotW / 2.0f;
            RectF slotRect = new RectF(slotX, trackRect.top + 4.0f, slotX + slotW, trackRect.bottom - 4.0f);

            // Scale graduation ticks on left & right of slot
            int numTicks = 9;
            float tickStep = slotRect.height() / (float)(numTicks - 1);
            paintStroke.setColor(Color.parseColor("#383C48"));
            paintStroke.setStrokeWidth(1.0f);
            for (int i = 0; i < numTicks; i++) {
                float ty = slotRect.top + i * tickStep;
                canvas.drawLine(slotX - 10.0f, ty, slotX - 3.0f, ty, paintStroke);
                canvas.drawLine(slotRect.right + 3.0f, ty, slotRect.right + 10.0f, ty, paintStroke);
            }
            // Deep recessed slot background
            paintFill.setShader(null);
            paintFill.setColor(Color.parseColor("#08090C"));
            canvas.drawRoundRect(slotRect, 6.0f, 6.0f, paintFill);
            paintStroke.setColor(Color.parseColor("#1C1E26"));
            paintStroke.setStrokeWidth(1.2f);
            canvas.drawRoundRect(slotRect, 6.0f, 6.0f, paintStroke);

            float travelH = slotRect.height() - 12.0f;
            float beamTop = 0, beamBottom = 0;
            float thumbW = Math.min(ctrl.width + 4.0f, 58.0f);
            float thumbH = 28.0f;
            float thumbX = trackRect.centerX() - thumbW / 2.0f;
            float thumbY = 0;

            if ("inverted".equals(fStyle)) {
                float fillH = travelH * pct;
                beamTop = slotRect.top + 6.0f;
                beamBottom = beamTop + fillH;
                thumbY = (slotRect.top + 6.0f) + fillH - (thumbH / 2.0f);
            } else if ("centered".equals(fStyle)) {
                // Center notch tick
                paintStroke.setColor(Color.parseColor("#4F5466"));
                paintStroke.setStrokeWidth(2.0f);
                canvas.drawLine(slotX - 6.0f, slotRect.centerY(), slotRect.right + 6.0f, slotRect.centerY(), paintStroke);

                if (pct >= 0.5f) {
                    beamBottom = slotRect.centerY();
                    beamTop = beamBottom - (pct - 0.5f) * travelH;
                } else {
                    beamTop = slotRect.centerY();
                    beamBottom = beamTop + (0.5f - pct) * travelH;
                }
                thumbY = (slotRect.bottom - 6.0f) - pct * travelH - (thumbH / 2.0f);
            } else {
                float fillH = travelH * pct;
                beamBottom = slotRect.bottom - 6.0f;
                beamTop = beamBottom - fillH;
                thumbY = (slotRect.bottom - 6.0f) - fillH - (thumbH / 2.0f);
            }

            // 3. Level & Glowing Neon Beam inside Slot
            if (Math.abs(beamBottom - beamTop) > 2.0f) {
                drawGlowingLine(canvas, slotRect.centerX(), beamBottom, slotRect.centerX(), beamTop, ctrl.accentColor, 3.5f);
            }

            // 4. Machined Aluminum Slider Thumb
            thumbY = Math.max(slotRect.top - 2.0f, Math.min(slotRect.bottom - thumbH + 2.0f, thumbY));
            RectF thumbRect = new RectF(thumbX, thumbY, thumbX + thumbW, thumbY + thumbH);

            // Tactile magnification while finger is pressing
            float tScale = (ctrl.faderThumbScale > 0.5f) ? ctrl.faderThumbScale : 1.0f;
            if (Math.abs(tScale - 1.0f) > 0.002f) {
                float tcx = thumbRect.centerX();
                float tcy = thumbRect.centerY();
                float halfW = (thumbW * tScale) / 2.0f;
                float halfH = (thumbH * tScale) / 2.0f;
                thumbRect.set(tcx - halfW, tcy - halfH, tcx + halfW, tcy + halfH);
            }

            float elevation = Math.max(0.0f, Math.min(1.0f, (tScale - 1.0f) / 0.15f));

            // Soft drop shadow (deepens and elevates when touched)
            paintFill.setShader(null);
            paintFill.setColor(Color.argb(Math.round(150 + 65 * elevation), 0, 0, 0));
            canvas.drawRoundRect(new RectF(thumbRect.left - 1.5f * elevation, thumbRect.top + 3.0f + 2.0f * elevation, thumbRect.right + 1.5f * elevation, thumbRect.bottom + 4.0f + 3.0f * elevation), 5.5f, 5.5f, paintFill);

            // Metallic Gunmetal Gradient
            LinearGradient metalGrad = new LinearGradient(
                thumbRect.left, thumbRect.top, thumbRect.left, thumbRect.bottom,
                new int[]{Color.parseColor("#444957"), Color.parseColor("#262832"), Color.parseColor("#1A1B21"), Color.parseColor("#101115")},
                new float[]{0.0f, 0.25f, 0.60f, 1.0f},
                Shader.TileMode.CLAMP
            );
            paintFill.setShader(metalGrad);
            canvas.drawRoundRect(thumbRect, 4.5f, 4.5f, paintFill);
            paintFill.setShader(null);

            // Beveled outline
            paintStroke.setColor(Color.parseColor("#5A6072"));
            paintStroke.setStrokeWidth(1.0f);
            canvas.drawRoundRect(thumbRect, 4.5f, 4.5f, paintStroke);

            // Elevated active neon bloom when touching
            if (elevation > 0.05f) {
                drawGlowingRoundRect(canvas, thumbRect, 4.5f, 4.5f, ctrl.accentColor, 1.8f * elevation);
            }

            // Subtle horizontal brush line
            paintStroke.setColor(Color.argb(20, 255, 255, 255));
            canvas.drawLine(thumbRect.left + 4.0f, thumbRect.centerY(), thumbRect.right - 4.0f, thumbRect.centerY(), paintStroke);

            // Center Horizontal Glowing Neon Slit
            float slitW = 16.0f * tScale;
            drawGlowingLine(canvas, thumbRect.centerX() - slitW / 2.0f, thumbRect.centerY(), thumbRect.centerX() + slitW / 2.0f, thumbRect.centerY(), ctrl.accentColor, 3.0f + 1.5f * elevation);
        }

        // 5. Bottom Track Mute Button (if configured)
        if (ctrl.hasBottomButton) {
            float btnH = 46.0f;
            float btnY = ctrl.y + ctrl.height - btnH;
            RectF btnRect = new RectF(ctrl.x + 2.0f, btnY, ctrl.x + ctrl.width - 2.0f, btnY + btnH);

            boolean isLit = ctrl.buttonValue;
            float btnActivation = (ctrl.animatedActivation >= 0f) ? ctrl.animatedActivation : (isLit ? 1.0f : 0.0f);
            float btnScale = (ctrl.buttonScale > 0.1f) ? ctrl.buttonScale : 1.0f;
            float btnCx = btnRect.centerX();
            float btnCy = btnRect.centerY();

            if (ctrl.buttonGlowAlpha > 0.01f) {
                float maxExp = 8.0f;
                float curExp = ctrl.buttonGlowProgress * maxExp;
                paintStroke.setStyle(Paint.Style.STROKE);
                paintStroke.setColor(adjustAlpha(ctrl.accentColor, ctrl.buttonGlowAlpha * 0.30f));
                paintStroke.setStrokeWidth(1.0f * (1.0f - ctrl.buttonGlowProgress * 0.6f));
                RectF waveR = new RectF(btnRect.left - curExp, btnRect.top - curExp, btnRect.right + curExp, btnRect.bottom + curExp);
                canvas.drawRoundRect(waveR, 8.0f + curExp * 0.5f, 8.0f + curExp * 0.5f, paintStroke);
            }

            canvas.save();
            if (Math.abs(btnScale - 1.0f) > 0.001f) {
                canvas.scale(btnScale, btnScale, btnCx, btnCy);
            }

            int baseCol = (ctrl.color == ctrl.accentColor) ? deriveDarkBaseColor(ctrl.accentColor) : ctrl.color;
            int faceCol = blendColors(Color.parseColor("#12141A"), baseCol, btnActivation);
            paintFill.setShader(null);
            paintFill.setColor(faceCol);
            canvas.drawRoundRect(btnRect, 8.0f, 8.0f, paintFill);

            int rimCol = blendColors(Color.parseColor("#262932"), ctrl.accentColor, Math.max(0.25f, btnActivation * 0.70f));
            paintStroke.setStyle(Paint.Style.STROKE);
            paintStroke.setColor(rimCol);
            paintStroke.setStrokeWidth(1.2f + 0.6f * btnActivation);
            canvas.drawRoundRect(btnRect, 8.0f, 8.0f, paintStroke);

            if (ctrl.buttonFlash > 0.01f) {
                paintFill.setColor(Color.argb(Math.round(ctrl.buttonFlash * 120), 255, 255, 255));
                canvas.drawRoundRect(btnRect, 8.0f, 8.0f, paintFill);
            }

            paintText.setTextSize(11.0f);
            paintText.setColor(blendColors(Color.parseColor("#666D7D"), Color.WHITE, btnActivation));
            canvas.drawText(isLit ? "ON" : "MUTE", btnCx, btnCy + 4.0f, paintText);

            canvas.restore();
        }
    }

    private void drawKnob(Canvas canvas, ControlModel ctrl) {
        float pillH = 26.0f;
        boolean hasLabel = ctrl.hasLabel;
        boolean isTop = "top".equalsIgnoreCase(ctrl.labelPosition);

        RectF dialArea;
        RectF pillRect = null;

        if (hasLabel) {
            if (isTop) {
                pillRect = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + pillH);
                dialArea = new RectF(ctrl.x, ctrl.y + pillH + 6.0f, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
            } else {
                pillRect = new RectF(ctrl.x, ctrl.y + ctrl.height - pillH, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
                dialArea = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + ctrl.height - pillH - 6.0f);
            }
        } else {
            dialArea = new RectF(ctrl.x, ctrl.y, ctrl.x + ctrl.width, ctrl.y + ctrl.height);
        }

        float dialSize = Math.min(dialArea.width(), dialArea.height());
        float cx = dialArea.centerX();
        float cy = dialArea.centerY();
        float radius = dialSize * 0.44f;

        // 1. Recessed Circular Well
        paintFill.setShader(null);
        paintFill.setColor(Color.parseColor("#08090C"));
        canvas.drawCircle(cx, cy, radius, paintFill);
        paintStroke.setColor(Color.parseColor("#1E2028"));
        paintStroke.setStrokeWidth(1.2f);
        canvas.drawCircle(cx, cy, radius, paintStroke);

        // 2. Glowing Neon Arc Meter / Outer Ring
        float haloRadius = radius * 0.90f;
        RectF arcRect = new RectF(cx - haloRadius, cy - haloRadius, cx + haloRadius, cy + haloRadius);

        // Inactive dark charcoal track
        paintStroke.setStrokeCap(Paint.Cap.ROUND);
        paintStroke.setColor(Color.parseColor("#1C1E26"));
        paintStroke.setStrokeWidth(4.0f);
        canvas.drawArc(arcRect, 135.0f, 270.0f, false, paintStroke);

        // Active glowing arc based on knobStyle
        float range = (ctrl.maxValue > ctrl.minValue) ? (ctrl.maxValue - ctrl.minValue) : 127.0f;
        float pct = (ctrl.value - ctrl.minValue) / range;
        pct = Math.max(0.0f, Math.min(1.0f, pct));

        String style = (ctrl.knobStyle != null) ? ctrl.knobStyle.toLowerCase() : "standard";
        float needleAngle = 135.0f + (pct * 270.0f);

        if ("inverted".equals(style)) {
            // Sweeps counter-clockwise from bottom-right (405°)
            if (pct > 0.01f) {
                drawGlowingArc(canvas, arcRect, 405.0f, -(pct * 270.0f), ctrl.accentColor, 4.0f);
            }
            needleAngle = 405.0f - (pct * 270.0f);
        } else if ("centered".equals(style)) {
            // Bipolar: sweeps outward from 12 o'clock center (270°)
            // Center notch tick
            paintStroke.setColor(Color.parseColor("#4F5466"));
            paintStroke.setStrokeWidth(2.0f);
            canvas.drawLine(cx, cy - haloRadius - 2.0f, cx, cy - haloRadius + 4.0f, paintStroke);

            if (pct >= 0.5f) {
                float sweep = (pct - 0.5f) * 270.0f;
                if (sweep > 1.0f) {
                    drawGlowingArc(canvas, arcRect, 270.0f, sweep, ctrl.accentColor, 4.0f);
                }
            } else {
                float sweep = (0.5f - pct) * 270.0f;
                if (sweep > 1.0f) {
                    drawGlowingArc(canvas, arcRect, 270.0f, -sweep, ctrl.accentColor, 4.0f);
                }
            }
            needleAngle = 135.0f + (pct * 270.0f);
        } else {
            // Standard: sweeps clockwise from bottom-left (135°)
            if (pct > 0.01f) {
                drawGlowingArc(canvas, arcRect, 135.0f, pct * 270.0f, ctrl.accentColor, 4.0f);
            }
            needleAngle = 135.0f + (pct * 270.0f);
        }

        // 3. Turned Aluminum Dial Face
        float dialFaceR = radius * 0.72f;
        paintFill.setShader(null);
        paintFill.setColor(Color.argb(160, 0, 0, 0));
        canvas.drawCircle(cx, cy + 2.0f, dialFaceR, paintFill); // drop shadow

        LinearGradient dialGrad = new LinearGradient(
            cx - dialFaceR, cy - dialFaceR, cx + dialFaceR, cy + dialFaceR,
            new int[]{Color.parseColor("#383C49"), Color.parseColor("#22242D"), Color.parseColor("#15161C"), Color.parseColor("#0C0D10")},
            new float[]{0.0f, 0.35f, 0.70f, 1.0f},
            Shader.TileMode.CLAMP
        );
        paintFill.setShader(dialGrad);
        canvas.drawCircle(cx, cy, dialFaceR, paintFill);
        paintFill.setShader(null);

        paintStroke.setColor(Color.parseColor("#4F5466"));
        paintStroke.setStrokeWidth(1.0f);
        canvas.drawCircle(cx, cy, dialFaceR, paintStroke);

        // Concentric brush groove
        paintStroke.setColor(Color.argb(12, 255, 255, 255));
        canvas.drawCircle(cx, cy, dialFaceR * 0.50f, paintStroke);

        // 4. Indicator Needle (Glowing Neon Pointer)
        String valDisplay = (ctrl.valueDisplay != null) ? ctrl.valueDisplay.toLowerCase() : "none";
        String valPos = (ctrl.valuePosition != null) ? ctrl.valuePosition.toLowerCase() : "center";
        boolean hasValueDisplay = !"none".equals(valDisplay);

        String valStr = "";
        if (hasValueDisplay) {
            if ("percent".equals(valDisplay)) {
                int p = Math.round(pct * 100.0f);
                valStr = p + "%";
            } else {
                float vRange = (ctrl.maxValue > ctrl.minValue) ? (ctrl.maxValue - ctrl.minValue) : 127.0f;
                int actualVal = Math.round(ctrl.minValue + (pct * vRange));
                valStr = String.valueOf(actualVal);
            }
        }
        boolean isCenterVal = hasValueDisplay && "center".equals(valPos);

        double rad = Math.toRadians(needleAngle);
        float needleStartR = isCenterVal ? (dialFaceR * 0.50f) : (dialFaceR * 0.20f);
        float pStartX = cx + (float)Math.cos(rad) * needleStartR;
        float pStartY = cy + (float)Math.sin(rad) * needleStartR;
        float pEndX = cx + (float)Math.cos(rad) * (dialFaceR * 0.85f);
        float pEndY = cy + (float)Math.sin(rad) * (dialFaceR * 0.85f);
        drawGlowingLine(canvas, pStartX, pStartY, pEndX, pEndY, ctrl.accentColor, 3.5f);

        // 5. Knob Value Readout (Center Cap or Bottom Badge)
        if (hasValueDisplay && !valStr.isEmpty()) {
            paintText.setLetterSpacing(0.0f);
            paintText.setTextAlign(Paint.Align.CENTER);

            if (isCenterVal) {
                // Center circular cap readout
                float centerR = dialFaceR * 0.46f;

                paintFill.setShader(null);
                paintFill.setColor(Color.parseColor("#12141A"));
                canvas.drawCircle(cx, cy, centerR, paintFill);

                paintStroke.setColor(adjustAlpha(ctrl.accentColor, 0.55f));
                paintStroke.setStrokeWidth(1.0f);
                canvas.drawCircle(cx, cy, centerR, paintStroke);

                float autoFontSize = Math.max(9.0f, Math.min(14.0f, centerR * 0.74f));
                float fontSize = (ctrl.valueFontSize > 0) ? ctrl.valueFontSize : autoFontSize;
                paintText.setColor(Color.WHITE);
                paintText.setTextSize(fontSize);
                paintText.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
                Paint.FontMetrics fm = paintText.getFontMetrics();
                float textBaseY = cy - (fm.ascent + fm.descent) / 2.0f;
                canvas.drawText(valStr, cx, textBaseY, paintText);
            } else {
                // Bottom badge pill
                float autoFontSize = 10.0f;
                float fontSize = (ctrl.valueFontSize > 0) ? ctrl.valueFontSize : autoFontSize;
                float badgeW = Math.max(42.0f, (float)valStr.length() * (fontSize * 0.85f) + 14.0f);
                float badgeH = Math.max(16.0f, fontSize + 6.0f);
                float badgeY;
                if (hasLabel && pillRect != null && !isTop) {
                    badgeY = pillRect.top - badgeH - 3.0f;
                } else {
                    badgeY = cy + radius + 3.0f;
                }
                RectF badgeRect = new RectF(cx - badgeW / 2.0f, badgeY, cx + badgeW / 2.0f, badgeY + badgeH);

                paintFill.setShader(null);
                paintFill.setColor(Color.parseColor("#0C0D12"));
                canvas.drawRoundRect(badgeRect, 4.0f, 4.0f, paintFill);

                paintStroke.setColor(adjustAlpha(ctrl.accentColor, 0.45f));
                paintStroke.setStrokeWidth(0.8f);
                canvas.drawRoundRect(badgeRect, 4.0f, 4.0f, paintStroke);

                paintText.setColor(ctrl.accentColor);
                paintText.setTextSize(fontSize);
                paintText.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
                Paint.FontMetrics fm = paintText.getFontMetrics();
                float textBaseY = badgeRect.centerY() - (fm.ascent + fm.descent) / 2.0f;
                canvas.drawText(valStr, badgeRect.centerX(), textBaseY, paintText);
            }
            paintText.setTypeface(Typeface.DEFAULT);
        }

        // 6. Draw Pill Label (Matching "SYNTH FILTER" capsule)
        if (hasLabel && pillRect != null) {
            paintFill.setShader(null);
            paintFill.setColor(Color.parseColor("#0A0B0E"));
            canvas.drawRoundRect(pillRect, 13.0f, 13.0f, paintFill);

            // Glowing border
            drawGlowingRoundRect(canvas, pillRect, 13.0f, 13.0f, ctrl.accentColor, 1.4f);

            float fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 11.0f;
            paintText.setColor(Color.WHITE);
            paintText.setTextSize(fSize);
            paintText.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
            paintText.setLetterSpacing(0.04f);

            canvas.save();
            canvas.clipRect(pillRect.left + 2.0f, pillRect.top + 1.0f, pillRect.right - 2.0f, pillRect.bottom - 1.0f);
            Paint.FontMetrics fm = paintText.getFontMetrics();
            float textBaseY = pillRect.centerY() - (fm.ascent + fm.descent) / 2.0f;
            canvas.drawText(ctrl.label != null ? ctrl.label : "", pillRect.centerX(), textBaseY, paintText);
            canvas.restore();
            paintText.setLetterSpacing(0.0f);
        }
    }

    private void drawButton(Canvas canvas, ControlModel ctrl) {
        boolean isCircle = "circle".equalsIgnoreCase(ctrl.shape);
        RectF r = ctrl.getRectF();

        float activation = (ctrl.animatedActivation >= 0f) ? ctrl.animatedActivation : (ctrl.value > 0 ? 1.0f : 0.0f);
        float scale = (ctrl.buttonScale > 0.1f) ? ctrl.buttonScale : 1.0f;
        float cx = r.centerX();
        float cy = r.centerY();

        // 1. Motion Graphics: Outer Expanding Shockwave Pulse Ring (discreet)
        if (ctrl.buttonGlowAlpha > 0.01f) {
            float maxExpand = 10.0f;
            float curExpand = ctrl.buttonGlowProgress * maxExpand;
            int shockColor = adjustAlpha(ctrl.accentColor, ctrl.buttonGlowAlpha * 0.35f);
            paintStroke.setStyle(Paint.Style.STROKE);
            paintStroke.setColor(shockColor);
            paintStroke.setStrokeWidth(1.0f * (1.0f - ctrl.buttonGlowProgress * 0.6f));
            if (isCircle) {
                float size = Math.min(r.width(), r.height());
                float radius = size / 2.0f;
                canvas.drawCircle(cx, cy, (radius - 2.0f) + curExpand, paintStroke);
            } else {
                float cornerR = 12.0f;
                RectF waveRect = new RectF(r.left - curExpand, r.top - curExpand, r.right + curExpand, r.bottom + curExpand);
                canvas.drawRoundRect(waveRect, cornerR + curExpand * 0.6f, cornerR + curExpand * 0.6f, paintStroke);
            }
        }

        // Apply Spring Scale Transformation around Center
        canvas.save();
        if (Math.abs(scale - 1.0f) > 0.001f) {
            canvas.scale(scale, scale, cx, cy);
        }

        if (isCircle) {
            float size = Math.min(r.width(), r.height());
            float radius = size / 2.0f;

            // Circular Recessed Well
            paintFill.setShader(null);
            paintFill.setColor(Color.parseColor("#08090C"));
            canvas.drawCircle(cx, cy, radius, paintFill);
            paintStroke.setColor(Color.parseColor("#20232C"));
            paintStroke.setStrokeWidth(1.2f);
            canvas.drawCircle(cx, cy, radius, paintStroke);

            // 360° Neon Halo Ring (crisp and discreet)
            float haloR = radius - 4.0f;
            float haloStroke = 1.4f + (0.8f * activation);
            int haloColor = blendColors(Color.parseColor("#1C1E26"), ctrl.accentColor, Math.max(0.25f, activation * 0.75f));
            paintStroke.setStyle(Paint.Style.STROKE);
            paintStroke.setColor(haloColor);
            paintStroke.setStrokeWidth(haloStroke);
            canvas.drawCircle(cx, cy, haloR, paintStroke);

            // Inner Face
            float faceR = haloR - 4.0f;
            int unlitFace = Color.parseColor("#15171D");
            int baseColor = (ctrl.color == ctrl.accentColor) ? deriveDarkBaseColor(ctrl.accentColor) : ctrl.color;
            int faceColor = blendColors(unlitFace, baseColor, activation);

            paintFill.setShader(null);
            paintFill.setColor(faceColor);
            canvas.drawCircle(cx, cy, faceR, paintFill);

            if (activation > 0.01f) {
                RadialGradient glowGrad = new RadialGradient(
                    cx, cy, faceR,
                    new int[]{adjustAlpha(ctrl.accentColor, 0.75f * activation), faceColor},
                    null, Shader.TileMode.CLAMP
                );
                paintFill.setShader(glowGrad);
                canvas.drawCircle(cx, cy, faceR, paintFill);
                paintFill.setShader(null);
            }

            paintStroke.setColor(Color.parseColor("#444957"));
            paintStroke.setStrokeWidth(1.0f);
            canvas.drawCircle(cx, cy, faceR, paintStroke);

            // Specular Flash Burst (soft and subtle)
            if (ctrl.buttonFlash > 0.01f) {
                int flashColor = Color.argb(Math.round(ctrl.buttonFlash * 120), 255, 255, 255);
                paintFill.setShader(null);
                paintFill.setColor(flashColor);
                canvas.drawCircle(cx, cy, faceR * 0.75f, paintFill);
            }

            // Circle Button Text Label (if present)
            if (ctrl.label != null && !ctrl.label.isEmpty()) {
                float fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 11.0f;
                int textColor = blendColors(adjustAlpha(ctrl.accentColor, 0.85f), Color.WHITE, activation);
                paintText.setColor(textColor);
                paintText.setTextSize(fSize);
                paintText.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
                paintText.setLetterSpacing(0.04f);

                canvas.save();
                Path circleClip = new Path();
                circleClip.addCircle(cx, cy, faceR - 2.0f, Path.Direction.CW);
                canvas.clipPath(circleClip);

                Paint.FontMetrics fm = paintText.getFontMetrics();
                float textBaseY = cy - (fm.ascent + fm.descent) / 2.0f;
                canvas.drawText(ctrl.label, cx, textBaseY, paintText);
                canvas.restore();
                paintText.setLetterSpacing(0.0f);
            }
        } else {
            // Square Illuminated Pad
            float cornerR = 12.0f;
            int unlitFace = Color.parseColor("#121318");
            int baseColor = (ctrl.color == ctrl.accentColor) ? deriveDarkBaseColor(ctrl.accentColor) : ctrl.color;
            int faceColor = blendColors(unlitFace, baseColor, activation);

            // Pad Interior Face
            paintFill.setShader(null);
            paintFill.setColor(faceColor);
            canvas.drawRoundRect(r, cornerR, cornerR, paintFill);

            if (activation > 0.01f) {
                RadialGradient glassGrad = new RadialGradient(
                    r.centerX(), r.centerY(), Math.max(r.width(), r.height()) * 0.7f,
                    new int[]{adjustAlpha(ctrl.accentColor, 0.85f * activation), faceColor},
                    null, Shader.TileMode.CLAMP
                );
                paintFill.setShader(glassGrad);
                canvas.drawRoundRect(r, cornerR, cornerR, paintFill);
                paintFill.setShader(null);
            }

            // Crisp, discreet Neon Rim (no heavy multi-layer blur)
            float rimStroke = 1.4f + (0.8f * activation);
            int rimColor = blendColors(Color.parseColor("#262932"), ctrl.accentColor, Math.max(0.25f, activation * 0.75f));
            paintStroke.setStyle(Paint.Style.STROKE);
            paintStroke.setColor(rimColor);
            paintStroke.setStrokeWidth(rimStroke);
            canvas.drawRoundRect(r, cornerR, cornerR, paintStroke);

            // Inner beveled highlight
            RectF innerR = new RectF(r.left + 2, r.top + 2, r.right - 2, r.bottom - 2);
            paintStroke.setColor(Color.argb(Math.round(25 + 65 * activation), 255, 255, 255));
            paintStroke.setStrokeWidth(1.0f);
            canvas.drawRoundRect(innerR, cornerR - 2.0f, cornerR - 2.0f, paintStroke);

            // Specular Flash Burst (soft and subtle)
            if (ctrl.buttonFlash > 0.01f) {
                int flashColor = Color.argb(Math.round(ctrl.buttonFlash * 120), 255, 255, 255);
                paintFill.setShader(null);
                paintFill.setColor(flashColor);
                RectF flashR = new RectF(r.left + 3, r.top + 3, r.right - 3, r.bottom - 3);
                canvas.drawRoundRect(flashR, cornerR - 2.0f, cornerR - 2.0f, paintFill);
            }

            // Button Text Label (Strictly clipped inside button borders, 1:1 scale matching macOS Editor)
            if (ctrl.label != null && !ctrl.label.isEmpty()) {
                float fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 13.0f;
                int textColor = blendColors(adjustAlpha(ctrl.accentColor, 0.85f), Color.WHITE, activation);
                paintText.setColor(textColor);
                paintText.setTextSize(fSize);
                paintText.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
                paintText.setLetterSpacing(0.04f);

                // Clip text strictly inside the button frame so it never exceeds the button borders
                canvas.save();
                canvas.clipRect(r.left + 3.0f, r.top + 2.0f, r.right - 3.0f, r.bottom - 2.0f);

                Paint.FontMetrics fm = paintText.getFontMetrics();
                float textBaseY = r.centerY() - (fm.ascent + fm.descent) / 2.0f;
                canvas.drawText(ctrl.label, r.centerX(), textBaseY, paintText);

                canvas.restore();
                paintText.setLetterSpacing(0.0f);
            }
        }

        canvas.restore();
    }

    private void drawXYPad(Canvas canvas, ControlModel ctrl) {
        RectF r = ctrl.getRectF();
        paintFill.setShader(null);
        paintFill.setColor(Color.parseColor("#08090C"));
        canvas.drawRoundRect(r, 14.0f, 14.0f, paintFill);

        // Glowing subtle outline
        drawGlowingRoundRect(canvas, r, 14.0f, 14.0f, adjustAlpha(ctrl.accentColor, 0.45f), 1.5f);

        float puckX = r.left + (ctrl.valueX / 127.0f) * r.width();
        float puckY = r.top + (1.0f - (ctrl.valueY / 127.0f)) * r.height();

        // Crosshairs
        paintStroke.setColor(Color.parseColor("#262934"));
        paintStroke.setStrokeWidth(1.0f);
        canvas.drawLine(puckX, r.top + 4.0f, puckX, r.bottom - 4.0f, paintStroke);
        canvas.drawLine(r.left + 4.0f, puckY, r.right - 4.0f, puckY, paintStroke);

        // Glowing Puck
        drawGlowingCircle(canvas, puckX, puckY, 11.0f, ctrl.accentColor, 3.5f);
        paintFill.setShader(null);
        paintFill.setColor(Color.WHITE);
        canvas.drawCircle(puckX, puckY, 4.0f, paintFill);

        if (ctrl.label != null && !ctrl.label.isEmpty()) {
            paintText.setColor(Color.parseColor("#8E8E93"));
            paintText.setTextSize(11.0f);
            canvas.drawText(ctrl.label, r.left + 16.0f, r.top + 18.0f, paintText);
        }
    }

    private void drawLabel(Canvas canvas, ControlModel ctrl) {
        RectF r = ctrl.getRectF();
        if (ctrl.hasBackground) {
            paintFill.setShader(null);
            paintFill.setColor(Color.parseColor("#0A0B0E"));
            canvas.drawRoundRect(r, 13.0f, 13.0f, paintFill);
            drawGlowingRoundRect(canvas, r, 13.0f, 13.0f, ctrl.accentColor, 1.2f);
        }

        float fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 12.5f;
        paintText.setColor(Color.WHITE);
        paintText.setTextSize(fSize);
        paintText.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        paintText.setLetterSpacing(0.04f);

        canvas.save();
        canvas.clipRect(r.left + 2.0f, r.top + 2.0f, r.right - 2.0f, r.bottom - 2.0f);
        Paint.FontMetrics fm = paintText.getFontMetrics();
        float textBaseY = r.centerY() - (fm.ascent + fm.descent) / 2.0f;
        canvas.drawText(ctrl.label != null ? ctrl.label : "", r.centerX(), textBaseY, paintText);
        canvas.restore();
        paintText.setLetterSpacing(0.0f);
    }

    private void drawVuMeter(Canvas canvas, ControlModel ctrl) {
        if (true) return;
        RectF r = ctrl.getRectF();

        // 1. Hardware Studio Enclosure (Chassis)
        paintFill.setShader(null);
        paintFill.setColor(Color.parseColor("#0C0E12"));
        canvas.drawRoundRect(r, 10.0f, 10.0f, paintFill);

        // Subtle glowing rim
        drawGlowingRoundRect(canvas, r, 10.0f, 10.0f, adjustAlpha(ctrl.accentColor, 0.35f), 1.2f);

        // 2. Channel Label Header
        float headerH = 26.0f;
        if (ctrl.hasLabel && ctrl.label != null && !ctrl.label.isEmpty()) {
            float fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 10.5f;
            paintText.setColor(Color.WHITE);
            paintText.setTextSize(fSize);
            paintText.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
            paintText.setLetterSpacing(0.04f);
            canvas.drawText(ctrl.label, r.centerX(), r.top + 16.0f, paintText);
            paintText.setLetterSpacing(0.0f);

            // Glowing LED accent line underneath header
            float barW = Math.min(26.0f, r.width() - 16.0f);
            float lineY = r.top + headerH - 2.0f;
            drawGlowingLine(canvas, r.centerX() - barW / 2.0f, lineY, r.centerX() + barW / 2.0f, lineY, ctrl.accentColor, 2.0f);
        } else {
            headerH = 8.0f;
        }

        // 3. Stereo Bars (Left and Right)
        float meterBottom = r.bottom - 12.0f;
        float meterTop = r.top + headerH + 6.0f;
        float meterH = meterBottom - meterTop;
        if (meterH < 20.0f) return;

        boolean isStereo = (r.width() >= 48.0f);
        int numLadders = isStereo ? 2 : 1;
        float ladderW = isStereo ? (r.width() - 28.0f) / 2.0f : (r.width() - 24.0f);
        if (ladderW > 14.0f) ladderW = 14.0f;

        float totalLadderW = numLadders * ladderW + (numLadders - 1) * 4.0f;
        float startLX = r.left + 8.0f;

        // dB Scale text on the right side
        String[] dbMarks = new String[] { "+6", "0", "-6", "-12", "-24", "-48" };
        float dbX = startLX + totalLadderW + 4.0f;
        float dbW = r.right - dbX - 2.0f;

        if (dbW > 10.0f) {
            paintText.setTextSize(8.0f);
            paintText.setColor(Color.parseColor("#727782"));
            paintText.setTextAlign(Paint.Align.LEFT);
            for (int m = 0; m < dbMarks.length; m++) {
                float my = meterTop + m * (meterH / (float) (dbMarks.length - 1)) + 3.0f;
                canvas.drawText(dbMarks[m], dbX, my, paintText);
            }
            paintText.setTextAlign(Paint.Align.CENTER);
        }

        // 4. Draw LED Segments
        int segments = 24;
        float segH = (meterH - (segments - 1) * 1.5f) / (float) segments;

        float currentVal = Math.max(0.0f, Math.min(1.0f, ctrl.vuLevel));

        for (int l = 0; l < numLadders; l++) {
            float lx = startLX + l * (ladderW + 4.0f);

            // Recessed slot background
            RectF slotRect = new RectF(lx - 1.0f, meterTop - 1.0f, lx + ladderW + 1.0f, meterBottom + 1.0f);
            paintFill.setStyle(Paint.Style.FILL);
            paintFill.setColor(Color.parseColor("#050608"));
            canvas.drawRoundRect(slotRect, 2.0f, 2.0f, paintFill);

            float ladderVal = (l == 1) ? Math.max(0.0f, Math.min(1.0f, currentVal * 0.95f)) : currentVal;

            for (int s = 0; s < segments; s++) {
                float sy = (meterBottom - segH) - s * (segH + 1.5f);
                RectF segRect = new RectF(lx, sy, lx + ladderW, sy + segH);

                float segPct = (float) s / (float) segments;
                boolean isLit = segPct <= ladderVal && ladderVal > 0.005f;

                int baseColor;
                if (ctrl.isMuted) {
                    baseColor = Color.parseColor("#7A8294");
                } else if (segPct > 0.88f) {
                    baseColor = Color.parseColor("#FF453A");
                } else if (segPct > 0.68f) {
                    baseColor = Color.parseColor("#FFD60A");
                } else {
                    baseColor = Color.parseColor("#30D158");
                }

                if (isLit) {
                    if (ctrl.isMuted) {
                        // Ableton Live Muted Gray Meter style (desaturated studio gray)
                        paintFill.setStyle(Paint.Style.FILL);
                        paintFill.setColor(Color.parseColor("#5A606E"));
                        canvas.drawRoundRect(segRect, 1.2f, 1.2f, paintFill);

                        // Subtle silver core filament
                        paintFill.setColor(Color.argb(130, 210, 215, 225));
                        RectF coreRect = new RectF(segRect.left + 1.0f, segRect.top + 0.6f, segRect.right - 1.0f, segRect.bottom - 0.6f);
                        canvas.drawRoundRect(coreRect, 0.6f, 0.6f, paintFill);

                        // Matte border without colored neon bloom
                        paintStroke.setStyle(Paint.Style.STROKE);
                        paintStroke.setColor(Color.parseColor("#3A3E47"));
                        paintStroke.setStrokeWidth(0.8f);
                        canvas.drawRoundRect(segRect, 1.2f, 1.2f, paintStroke);
                    } else {
                        // Solid filled vivid LED block
                        paintFill.setStyle(Paint.Style.FILL);
                        paintFill.setColor(baseColor);
                        canvas.drawRoundRect(segRect, 1.2f, 1.2f, paintFill);

                        // Hot center core filament
                        paintFill.setColor(Color.argb(170, 255, 255, 255));
                        RectF coreRect = new RectF(segRect.left + 1.0f, segRect.top + 0.6f, segRect.right - 1.0f, segRect.bottom - 0.6f);
                        canvas.drawRoundRect(coreRect, 0.6f, 0.6f, paintFill);

                        // Glowing bloom outline
                        paintStroke.setStyle(Paint.Style.STROKE);
                        paintStroke.setColor(adjustAlpha(baseColor, 0.50f));
                        paintStroke.setStrokeWidth(1.4f);
                        canvas.drawRoundRect(segRect, 1.2f, 1.2f, paintStroke);
                    }
                } else {
                    // Dark unlit segment in groove
                    paintFill.setStyle(Paint.Style.FILL);
                    paintFill.setColor(ctrl.isMuted ? Color.parseColor("#0E1014") : Color.argb(32, Color.red(baseColor), Color.green(baseColor), Color.blue(baseColor)));
                    canvas.drawRoundRect(segRect, 1.2f, 1.2f, paintFill);

                    paintStroke.setStyle(Paint.Style.STROKE);
                    paintStroke.setColor(Color.parseColor("#15181E"));
                    paintStroke.setStrokeWidth(0.6f);
                    canvas.drawRoundRect(segRect, 1.2f, 1.2f, paintStroke);
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Multi-Touch Interaction
    // -----------------------------------------------------------------
    @Override
    public boolean onTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        int pointerIndex = event.getActionIndex();
        int pointerId = event.getPointerId(pointerIndex);

        float rawX = event.getX(pointerIndex);
        float rawY = event.getY(pointerIndex);

        if (isTransitioning) {
            return true; // Ignore control touches while smoothly animating
        }

        boolean hasMultipleTabs = (layout != null && layout.pages != null && layout.pages.size() > 1);
        float bottomZoneH = dp(32);

        // Check if user initiated bottom tab bar slide gesture
        boolean inTabGestureZone = hasMultipleTabs
                && rawY >= (canvasOriginY + availableH - bottomZoneH)
                && rawY <= (canvasOriginY + availableH)
                && rawX >= canvasOriginX
                && rawX <= (canvasOriginX + availableW);

        if (inTabGestureZone) {
            if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_POINTER_DOWN) {
                isBottomSwipeActive = true;
                bottomSwipePointerId = pointerId;
                bottomSwipeStartX = rawX;
                bottomSwipeStartY = rawY;
                isDraggingPage = false;
                dragInBaseUnits = 0f;
                if (pageAnimator != null && pageAnimator.isRunning()) {
                    pageAnimator.cancel();
                }
                invalidate();
                return true;
            }
        }

        if (isBottomSwipeActive) {
            int bIdx = event.findPointerIndex(bottomSwipePointerId);
            if (bIdx >= 0 && action == MotionEvent.ACTION_MOVE) {
                float curX = event.getX(bIdx);
                float dx = curX - bottomSwipeStartX;
                if (!isDraggingPage && Math.abs(dx) > dp(6)) {
                    isDraggingPage = true;
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
                    if (transitionFromBitmap == null || cachedFromIndex != layout.activePageIndex) {
                        if (transitionFromBitmap != null) transitionFromBitmap.recycle();
                        transitionFromBitmap = createPageBitmap(layout.getActivePage());
                        cachedFromIndex = layout.activePageIndex;
                    }
                }
                if (isDraggingPage) {
                    float baseW = (layout.canvasWidth > 0) ? layout.canvasWidth : 920.0f;
                    float baseDx = dx / scale;
                    if (layout.activePageIndex == 0 && baseDx > 0) {
                        baseDx *= 0.35f;
                    } else if (layout.activePageIndex == layout.pages.size() - 1 && baseDx < 0) {
                        baseDx *= 0.35f;
                    }
                    dragInBaseUnits = baseDx;

                    int targetIdx = (baseDx < 0) ? layout.activePageIndex + 1 : layout.activePageIndex - 1;
                    if (targetIdx >= 0 && targetIdx < layout.pages.size()) {
                        if (transitionToBitmap == null || cachedToIndex != targetIdx) {
                            if (transitionToBitmap != null) transitionToBitmap.recycle();
                            transitionToBitmap = createPageBitmap(layout.pages.get(targetIdx));
                            cachedToIndex = targetIdx;
                        }
                    }
                    invalidate();
                }
                return true;
            } else if (pointerId == bottomSwipePointerId && (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_POINTER_UP || action == MotionEvent.ACTION_CANCEL)) {
                float dx = rawX - bottomSwipeStartX;
                float threshold = dp(28);
                if (isDraggingPage) {
                    if (dx < -threshold && layout.activePageIndex < layout.pages.size() - 1) {
                        isDraggingPage = false;
                        animateToPage(layout.activePageIndex + 1);
                    } else if (dx > threshold && layout.activePageIndex > 0) {
                        isDraggingPage = false;
                        animateToPage(layout.activePageIndex - 1);
                    } else {
                        animateBackToCurrentPage();
                    }
                } else if (action == MotionEvent.ACTION_UP) {
                    RectF expandedBar = new RectF(bottomTabBarRect);
                    expandedBar.inset(-dp(14), -dp(14));
                    boolean hitBar = expandedBar.contains(rawX, rawY);
                    if (hitBar) {
                        int numPages = layout.pages.size();
                        float totalDotsW = (numPages - 1) * dp(16);
                        float startX = bottomTabBarRect.centerX() - (totalDotsW / 2.0f);
                        int tappedIndex = Math.round((rawX - startX) / dp(16));
                        if (tappedIndex >= 0 && tappedIndex < numPages && tappedIndex != layout.activePageIndex) {
                            animateToPage(tappedIndex);
                        }
                    }
                    recycleTransitionBitmaps();
                } else {
                    recycleTransitionBitmaps();
                }
                isBottomSwipeActive = false;
                bottomSwipePointerId = -1;
                invalidate();
                return true;
            }
        }

        // Check sidebar buttons and tab flyout modal
        if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_POINTER_DOWN) {
            // 1. If tab flyout is open
            if (isTabFlyoutOpen) {
                if (flyoutCardRect.contains(rawX, rawY)) {
                    for (int i = 0; i < tabFlyoutItemRects.size(); i++) {
                        if (tabFlyoutItemRects.get(i).contains(rawX, rawY)) {
                            performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                            if (layout != null) {
                                animateToPage(i);
                            }
                            isTabFlyoutOpen = false;
                            invalidate();
                            return true;
                        }
                    }
                    return true;
                } else if (tabsButtonRect.contains(rawX, rawY)) {
                    performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    isTabFlyoutOpen = false;
                    invalidate();
                    return true;
                } else {
                    // Tap outside dismisses flyout
                    isTabFlyoutOpen = false;
                    invalidate();
                    if (sidebarRect.contains(rawX, rawY)) {
                        return true;
                    }
                }
            }

            // 2. Settings Button
            if (settingsButtonRect.contains(rawX, rawY)) {
                performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                isTabFlyoutOpen = false;
                if (onSettingsClickedListener != null) {
                    onSettingsClickedListener.run();
                }
                return true;
            }

            // 3. Tabs Button
            if (tabsButtonRect.contains(rawX, rawY)) {
                performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                if (layout != null && layout.pages != null && layout.pages.size() > 1) {
                    isTabFlyoutOpen = !isTabFlyoutOpen;
                    invalidate();
                }
                return true;
            }

            // 4. Any other tap within sidebar / bottom bar should not bleed into controls
            if (sidebarRect.contains(rawX, rawY)) {
                return true;
            }
        }

        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                float touchX = (rawX - offsetX) / scale;
                float touchY = (rawY - offsetY) / scale;

                ControlModel hit = findHitControl(touchX, touchY);
                if (hit != null) {
                    TouchState state = new TouchState();
                    state.control = hit;
                    state.startY = touchY;
                    state.initialVal = hit.value;

                    if ("fader".equals(hit.type) && hit.hasBottomButton) {
                        float btnSize = 56.0f;
                        float btnY = hit.y + hit.height - btnSize;
                        if (touchY >= btnY) {
                            state.isBottomButton = true;
                            handleFaderButtonTouch(hit);
                            activeTouches.put(pointerId, state);
                            invalidate();
                            return true;
                        }
                    }

                    if ("button".equals(hit.type)) {
                        handlePadButtonDown(hit);
                    } else if ("fader".equals(hit.type)) {
                        setFaderPressed(hit, true);
                        updateFaderTouch(hit, touchX, touchY);
                    } else if ("xypad".equals(hit.type)) {
                        updateXYTouch(hit, touchX, touchY);
                    }

                    performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    activeTouches.put(pointerId, state);
                    invalidate();
                }
                return true;
            }

            case MotionEvent.ACTION_MOVE: {
                for (int i = 0; i < event.getPointerCount(); i++) {
                    int pId = event.getPointerId(i);
                    TouchState state = activeTouches.get(pId);
                    if (state != null && state.control != null && !state.isBottomButton) {
                        float touchX = (event.getX(i) - offsetX) / scale;
                        float touchY = (event.getY(i) - offsetY) / scale;

                        if ("fader".equals(state.control.type)) {
                            updateFaderTouch(state.control, touchX, touchY);
                        } else if ("knob".equals(state.control.type)) {
                            float deltaY = state.startY - touchY;
                            float range = state.control.maxValue - state.control.minValue;
                            float newVal = state.initialVal + (deltaY / 120.0f) * range;
                            state.control.value = Math.max(state.control.minValue, Math.min(state.control.maxValue, newVal));
                            if (networkManager != null) {
                                networkManager.sendCC(state.control.midiChannel, state.control.midiNumber, Math.round(state.control.value));
                            }
                        } else if ("xypad".equals(state.control.type)) {
                            updateXYTouch(state.control, touchX, touchY);
                        }
                    }
                }
                invalidate();
                return true;
            }

            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_UP: {
                TouchState state = activeTouches.remove(pointerId);
                if (state != null && state.control != null) {
                    if ("fader".equals(state.control.type)) {
                        boolean stillHeld = false;
                        for (TouchState s : activeTouches.values()) {
                            if (s.control == state.control) {
                                stillHeld = true;
                                break;
                            }
                        }
                        if (!stillHeld) {
                            setFaderPressed(state.control, false);
                        }
                    } else if ("button".equals(state.control.type)) {
                        handlePadButtonUp(state.control);
                    }
                }
                if (activeTouches.isEmpty()) {
                    scheduleStateSave();
                }
                invalidate();
                return true;
            }

            case MotionEvent.ACTION_CANCEL: {
                for (TouchState state : activeTouches.values()) {
                    if ("fader".equals(state.control.type)) {
                        setFaderPressed(state.control, false);
                    } else if ("button".equals(state.control.type)) {
                        handlePadButtonUp(state.control);
                    }
                }
                activeTouches.clear();
                scheduleStateSave();
                invalidate();
                return true;
            }
        }

        return super.onTouchEvent(event);
    }

    private ControlModel findHitControl(float x, float y) {
        if (layout == null || layout.controls == null) return null;
        for (int i = layout.controls.size() - 1; i >= 0; i--) {
            ControlModel m = layout.controls.get(i);
            if (m.getRectF().contains(x, y)) return m;
        }
        return null;
    }

    private void updateFaderTouch(ControlModel ctrl, float touchX, float touchY) {
        boolean isHorizontal = "horizontal".equalsIgnoreCase(ctrl.orientation);
        String fStyle = (ctrl.faderStyle != null) ? ctrl.faderStyle.toLowerCase() : "standard";
        float pct;

        if (isHorizontal) {
            float trackLeft = ctrl.x + 4.0f;
            float trackRight = ctrl.x + ctrl.width - 4.0f;
            float trackW = trackRight - trackLeft;
            if (trackW < 10.0f) trackW = 10.0f;
            if ("inverted".equals(fStyle)) {
                pct = (trackRight - touchX) / trackW;
            } else {
                pct = (touchX - trackLeft) / trackW;
            }
        } else {
            float pillH = 26.0f;
            boolean hasLabel = ctrl.hasLabel;
            boolean isBottom = "bottom".equalsIgnoreCase(ctrl.labelPosition);

            float trackTop;
            float trackBottom;

            if (hasLabel) {
                if (isBottom) {
                    trackTop = ctrl.y;
                    trackBottom = ctrl.y + ctrl.height - pillH - 8.0f;
                } else {
                    trackTop = ctrl.y + pillH + 8.0f;
                    trackBottom = ctrl.y + ctrl.height;
                }
            } else {
                trackTop = ctrl.y;
                trackBottom = ctrl.y + ctrl.height;
            }

            if (ctrl.hasBottomButton) {
                trackBottom -= 64.0f;
            }

            float trackH = trackBottom - trackTop;
            if (trackH < 10.0f) trackH = 10.0f;
            if ("inverted".equals(fStyle)) {
                pct = (touchY - trackTop) / trackH;
            } else {
                pct = (trackBottom - touchY) / trackH;
            }
        }

        pct = Math.max(0.0f, Math.min(1.0f, pct));
        ctrl.value = Math.round(ctrl.minValue + pct * (ctrl.maxValue - ctrl.minValue));

        // When moving the fader, the meter cannot exceed the fader's physical level
        if (pct <= 0.005f) {
            ctrl.vuLevel = 0.0f;
            ctrl.peakLevel = 0.0f;
            ctrl.targetVuLevel = 0.0f;
        } else if (ctrl.vuLevel > pct) {
            ctrl.vuLevel = pct;
            ctrl.peakLevel = Math.min(ctrl.peakLevel, pct);
            ctrl.targetVuLevel = Math.min(ctrl.targetVuLevel, pct);
        }

        if (networkManager != null) {
            networkManager.sendCC(ctrl.midiChannel, ctrl.midiNumber, (int) ctrl.value);
        }
    }

    private void handlePadButtonDown(ControlModel ctrl) {
        boolean isCC = "cc".equalsIgnoreCase(ctrl.midiType);
        int onVal = (ctrl.maxValue > 0) ? ctrl.maxValue : 127;
        int offVal = (ctrl.minValue >= 0) ? ctrl.minValue : 0;

        if ("toggle".equals(ctrl.mode)) {
            ctrl.value = (ctrl.value > offVal) ? offVal : onVal;
            ctrl.isMuted = (ctrl.value == offVal);
            syncFaderMuteFromButton(ctrl);
            animateButtonTrigger(ctrl, ctrl.value > offVal);
            scheduleStateSave();

            if (networkManager != null) {
                if (isCC) {
                    networkManager.sendCC(ctrl.midiChannel, ctrl.midiNumber, (int) ctrl.value);
                } else {
                    // Send Note On to trigger DAW toggle switch
                    networkManager.sendNoteOn(ctrl.midiChannel, ctrl.midiNumber, onVal);
                }
            }
        } else {
            ctrl.value = onVal;
            animateButtonTrigger(ctrl, true);
            if (networkManager != null) {
                if (isCC) {
                    networkManager.sendCC(ctrl.midiChannel, ctrl.midiNumber, onVal);
                } else {
                    networkManager.sendNoteOn(ctrl.midiChannel, ctrl.midiNumber, onVal);
                }
            }
        }
    }

    private void handlePadButtonUp(ControlModel ctrl) {
        boolean isCC = "cc".equalsIgnoreCase(ctrl.midiType);
        int offVal = (ctrl.minValue >= 0) ? ctrl.minValue : 0;

        if ("toggle".equals(ctrl.mode)) {
            if (!isCC) {
                // For Note toggles, release note so DAW receives a complete NoteOn->NoteOff pulse on each tap
                if (networkManager != null) networkManager.sendNoteOff(ctrl.midiChannel, ctrl.midiNumber);
            }
        } else {
            ctrl.value = offVal;
            animateButtonTrigger(ctrl, false);
            if (networkManager != null) {
                if (isCC) {
                    networkManager.sendCC(ctrl.midiChannel, ctrl.midiNumber, offVal);
                } else {
                    networkManager.sendNoteOff(ctrl.midiChannel, ctrl.midiNumber);
                }
            }
        }
    }

    private void handleFaderButtonTouch(ControlModel ctrl) {
        ctrl.buttonValue = !ctrl.buttonValue;
        ctrl.isMuted = !ctrl.buttonValue;
        animateButtonTrigger(ctrl, ctrl.buttonValue);
        scheduleStateSave();
        int note = ctrl.buttonMidiNumber;
        if (networkManager != null) {
            networkManager.sendNoteOn(ctrl.midiChannel, note, 127);
            postDelayed(() -> {
                if (networkManager != null) networkManager.sendNoteOff(ctrl.midiChannel, note);
            }, 50);
        }
    }

    private void syncFaderMuteFromButton(ControlModel btn) {
        List<ControlModel> all = getAllControls();
        for (ControlModel f : all) {
            if ("fader".equals(f.type) || "vu".equals(f.type)) {
                boolean match = false;
                if (btn.id != null && f.id != null) {
                    String bBase = btn.id.replace("btn_", "").replace("pad_", "");
                    String fBase = f.id.replace("fader_", "").replace("vu_", "");
                    if (bBase.equalsIgnoreCase(fBase)) match = true;
                }
                int fTrack = (f.vuMidiNumber > 0) ? f.vuMidiNumber : f.midiChannel;
                int bTrack = (btn.vuMidiNumber > 0) ? btn.vuMidiNumber : btn.midiChannel;
                if (fTrack == bTrack) match = true;
                if (btn.midiNumber >= 16 && btn.midiNumber <= 23 && fTrack == (btn.midiNumber - 16 + 1)) {
                    match = true;
                }
                if (btn.midiNumber >= 48 && btn.midiNumber <= 55 && fTrack == (btn.midiNumber - 48 + 1)) {
                    match = true;
                }
                if (match) {
                    f.isMuted = btn.isMuted;
                }
            }
        }
    }

    private void updateXYTouch(ControlModel ctrl, float touchX, float touchY) {
        RectF r = ctrl.getRectF();
        float pctX = Math.max(0.0f, Math.min(1.0f, (touchX - r.left) / r.width()));
        float pctY = Math.max(0.0f, Math.min(1.0f, (r.bottom - touchY) / r.height()));
        ctrl.valueX = Math.round(pctX * 127);
        ctrl.valueY = Math.round(pctY * 127);

        if (networkManager != null) {
            networkManager.sendCC(ctrl.midiChannel, 1, (int) ctrl.valueX);
            networkManager.sendCC(ctrl.midiChannel, 2, (int) ctrl.valueY);
        }
    }

    private float dp(float val) {
        return val * getResources().getDisplayMetrics().density;
    }
}
