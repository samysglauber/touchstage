package com.airmidi.controller;

import android.content.Context;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

public class PresetManager {

    public static class PresetItem {
        public final String id;
        public final String name;
        public final String assetPath;
        public final File file;
        public final boolean isCustom;

        public PresetItem(String id, String name, String assetPath, File file, boolean isCustom) {
            this.id = id;
            this.name = name;
            this.assetPath = assetPath;
            this.file = file;
            this.isCustom = isCustom;
        }
    }

    public static File getPresetsDir(Context ctx) {
        File dir = new File(ctx.getFilesDir(), "presets");
        if (!dir.exists()) {
            dir.mkdirs();
        }
        return dir;
    }

    public static List<PresetItem> getAllPresets(Context ctx) {
        List<PresetItem> list = new ArrayList<>();

        // 1. Built-in presets (Only the first primary preset)
        list.add(new PresetItem("builtin_stage6", "Stage 6-Track", "preset_stage6.json", null, false));

        // 2. Custom user presets stored on device
        File dir = getPresetsDir(ctx);
        File[] files = dir.listFiles((d, name) -> name.toLowerCase().endsWith(".json"));
        if (files != null) {
            for (File f : files) {
                String presetName = getPresetNameFromFile(f);
                if (presetName == null || presetName.isEmpty()) {
                    presetName = f.getName().replace(".json", "").replace("_", " ");
                }
                list.add(new PresetItem(f.getName(), presetName, null, f, true));
            }
        }

        return list;
    }

    public static boolean hasPreset(Context ctx, String layoutName) {
        if (layoutName == null || layoutName.trim().isEmpty()) return false;
        String target = layoutName.trim().toLowerCase();

        for (PresetItem p : getAllPresets(ctx)) {
            if (p.name != null && p.name.trim().toLowerCase().equals(target)) {
                return true;
            }
        }
        return false;
    }

    public static boolean savePreset(Context ctx, LayoutModel layout) {
        if (layout == null) return false;
        try {
            String rawName = layout.name != null && !layout.name.trim().isEmpty() ? layout.name.trim() : "Custom_Layout";
            String safeName = rawName.replaceAll("[^a-zA-Z0-9_\\- ]", "").trim().replace(" ", "_");
            if (safeName.isEmpty()) safeName = "Custom_Layout";

            File file = new File(getPresetsDir(ctx), safeName + ".json");
            String json = layout.toJsonString();
            FileOutputStream fos = new FileOutputStream(file);
            fos.write(json.getBytes(StandardCharsets.UTF_8));
            fos.close();
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public static LayoutModel loadPreset(Context ctx, PresetItem item) {
        if (item == null) return null;
        if (item.isCustom && item.file != null) {
            return LayoutModel.loadFromFile(item.file);
        } else if (item.assetPath != null) {
            return LayoutModel.loadFromAsset(ctx, item.assetPath);
        }
        return null;
    }

    public static boolean deletePreset(PresetItem item) {
        if (item != null && item.isCustom && item.file != null && item.file.exists()) {
            return item.file.delete();
        }
        return false;
    }

    private static String getPresetNameFromFile(File f) {
        try {
            FileInputStream fis = new FileInputStream(f);
            byte[] buf = new byte[(int) f.length()];
            fis.read(buf);
            fis.close();
            JSONObject obj = new JSONObject(new String(buf, StandardCharsets.UTF_8));
            return obj.optString("name", null);
        } catch (Exception ignored) {
            return null;
        }
    }
}
