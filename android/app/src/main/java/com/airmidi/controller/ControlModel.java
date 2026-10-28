package com.airmidi.controller;

import android.graphics.Color;
import android.graphics.RectF;
import org.json.JSONObject;

public class ControlModel {
    public String id;
    public String type; // "fader", "knob", "button", "xypad", "label"
    public String label;
    public float x;
    public float y;
    public float width;
    public float height;
    public int color;
    public int accentColor;
    public int midiChannel = 1;
    public String midiType = "cc";
    public int midiNumber = 7;
    public int minValue = 0;
    public int maxValue = 127;
    public float value = 0;

    // Fader extra options
    public boolean hasLabel = false;
    public String labelPosition = "top"; // "top", "bottom"
    public String orientation = "vertical"; // "vertical", "horizontal" (for faders)
    public String knobStyle = "standard"; // "standard", "inverted", "centered" (for knobs)
    public String faderStyle = "standard"; // "standard", "inverted", "centered" (for faders)
    public float fontSize = 0; // custom font size (0 = auto)
    public String shape = "square"; // "square", "circle"
    public boolean hasBackground = false; // for label controls
    public boolean hasVuMeter = false; // integrated VU meter
    public int vuMidiChannel = 1;
    public int vuMidiNumber = 7;
    public float vuLevel = 0.0f; // live VU level 0.0 - 1.0
    public float targetVuLevel = 0.0f; // target level from DAW
    public float peakLevel = 0.0f; // live peak hold level 0.0 - 1.0
    public boolean hasBottomButton = false;
    public int buttonMidiNumber = 60;
    public String buttonMode = "toggle";
    public boolean buttonValue = false;
    public boolean isMuted = false; // Ableton-style track mute state

    // Button mode
    public String mode = "momentary";

    // XY Pad
    public float valueX = 64;
    public float valueY = 64;

    // Tactile animations (Transient)
    public float faderThumbScale = 1.0f;
    public boolean isFaderPressed = false;
    public android.animation.ValueAnimator faderThumbAnimator;

    // Button motion graphics (Transient)
    public float buttonScale = 1.0f;
    public float buttonGlowProgress = 0.0f;
    public float buttonGlowAlpha = 0.0f;
    public float buttonFlash = 0.0f;
    public float animatedActivation = -1.0f;
    public android.animation.ValueAnimator buttonAnimator;

    public RectF getRectF() {
        return new RectF(x, y, x + width, y + height);
    }

    public static ControlModel fromJson(JSONObject json) {
        ControlModel m = new ControlModel();
        m.id = json.optString("id", "ctrl_" + System.currentTimeMillis());
        m.type = json.optString("type", "fader");
        m.label = json.optString("label", "CONTROL");
        m.x = (float) json.optDouble("x", 0);
        m.y = (float) json.optDouble("y", 0);
        m.width = (float) json.optDouble("width", 80);
        m.height = (float) json.optDouble("height", 200);

        m.color = parseColor(json.optString("color", "#005f6b"));
        m.accentColor = parseColor(json.optString("accentColor", "#00d2d3"));

        m.midiChannel = json.optInt("midiChannel", 1);
        m.midiType = json.optString("midiType", "cc");
        m.midiNumber = json.optInt("midiNumber", 7);
        m.minValue = json.optInt("minValue", 0);
        m.maxValue = json.optInt("maxValue", 127);
        m.value = (float) json.optDouble("value", 0);

        m.hasLabel = json.optBoolean("hasLabel", false);
        m.labelPosition = json.optString("labelPosition", "knob".equals(m.type) ? "bottom" : "top");
        m.orientation = json.optString("orientation", "vertical");
        m.knobStyle = json.optString("knobStyle", "standard");
        m.faderStyle = json.optString("faderStyle", "standard");
        m.fontSize = (float) json.optDouble("fontSize", 0);
        m.shape = json.optString("shape", "square");
        m.hasBackground = json.optBoolean("hasBackground", false);
        m.hasVuMeter = json.optBoolean("hasVuMeter", false);
        m.vuMidiChannel = json.optInt("vuMidiChannel", m.midiChannel);
        m.vuMidiNumber = json.optInt("vuMidiNumber", m.midiNumber);
        m.hasBottomButton = json.optBoolean("hasBottomButton", false);
        m.buttonMidiNumber = json.optInt("buttonMidiNumber", 60);
        m.buttonMode = json.optString("buttonMode", "toggle");
        m.buttonValue = json.optBoolean("buttonValue", false);
        m.isMuted = json.optBoolean("isMuted", false);
        m.mode = json.optString("mode", "momentary");
        m.valueX = (float) json.optDouble("valueX", 64);
        m.valueY = (float) json.optDouble("valueY", 64);
        return m;
    }

    public JSONObject toJson() {
        JSONObject obj = new JSONObject();
        try {
            obj.put("id", id);
            obj.put("type", type);
            obj.put("label", label);
            obj.put("x", x);
            obj.put("y", y);
            obj.put("width", width);
            obj.put("height", height);
            obj.put("color", String.format("#%06X", (0xFFFFFF & color)));
            obj.put("accentColor", String.format("#%06X", (0xFFFFFF & accentColor)));
            obj.put("midiChannel", midiChannel);
            obj.put("midiType", midiType);
            obj.put("midiNumber", midiNumber);
            obj.put("minValue", minValue);
            obj.put("maxValue", maxValue);
            obj.put("value", value);
            obj.put("hasLabel", hasLabel);
            obj.put("labelPosition", labelPosition);
            obj.put("orientation", orientation);
            obj.put("knobStyle", knobStyle);
            obj.put("faderStyle", faderStyle);
            if (fontSize > 0) obj.put("fontSize", fontSize);
            if (hasVuMeter) {
                obj.put("hasVuMeter", true);
                if (vuMidiNumber > 0) obj.put("vuMidiNumber", vuMidiNumber);
                if (vuMidiChannel > 0) obj.put("vuMidiChannel", vuMidiChannel);
            }
            obj.put("shape", shape);
            obj.put("hasBackground", hasBackground);
            obj.put("hasBottomButton", hasBottomButton);
            obj.put("buttonMidiNumber", buttonMidiNumber);
            obj.put("buttonMode", buttonMode);
            obj.put("buttonValue", buttonValue);
            obj.put("isMuted", isMuted);
            obj.put("mode", mode);
            obj.put("valueX", valueX);
            obj.put("valueY", valueY);
        } catch (Exception ignored) {}
        return obj;
    }

    private static int parseColor(String hex) {
        try {
            if (hex == null || hex.isEmpty()) return Color.CYAN;
            if (!hex.startsWith("#")) hex = "#" + hex;
            return Color.parseColor(hex);
        } catch (Exception e) {
            return Color.CYAN;
        }
    }
}
