package com.airmidi.controller;

import android.content.Context;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

public class LayoutModel {

    public static class PageModel {
        public String id;
        public String name;
        public List<ControlModel> controls = new ArrayList<>();

        public static PageModel fromJson(JSONObject json) {
            PageModel p = new PageModel();
            p.id = json.optString("id", "page_" + System.currentTimeMillis());
            p.name = json.optString("name", "Screen");
            JSONArray arr = json.optJSONArray("controls");
            if (arr != null) {
                for (int i = 0; i < arr.length(); i++) {
                    JSONObject cObj = arr.optJSONObject(i);
                    if (cObj != null) {
                        p.controls.add(ControlModel.fromJson(cObj));
                    }
                }
            }
            return p;
        }

        public JSONObject toJson() {
            JSONObject obj = new JSONObject();
            try {
                obj.put("id", id != null ? id : "page_0");
                obj.put("name", name != null ? name : "Screen");
                JSONArray arr = new JSONArray();
                if (controls != null) {
                    for (ControlModel c : controls) {
                        arr.put(c.toJson());
                    }
                }
                obj.put("controls", arr);
            } catch (Exception ignored) {}
            return obj;
        }
    }

    public String name = "Default Layout";
    public String author = "AirMIDI";
    public String version = "1.0";
    public float canvasWidth = 920.0f;
    public float canvasHeight = 460.0f;
    public List<PageModel> pages = new ArrayList<>();
    public int activePageIndex = 0;
    public List<ControlModel> controls = new ArrayList<>();

    public void setActivePageIndex(int index) {
        if (pages != null && !pages.isEmpty()) {
            if (index >= 0 && index < pages.size()) {
                activePageIndex = index;
                controls = pages.get(index).controls;
            }
        }
    }

    public PageModel getActivePage() {
        if (pages == null || pages.isEmpty()) {
            PageModel def = new PageModel();
            def.name = "Screen 1";
            def.controls = (controls != null) ? controls : new ArrayList<>();
            pages = new ArrayList<>();
            pages.add(def);
            activePageIndex = 0;
            return def;
        }
        if (activePageIndex < 0 || activePageIndex >= pages.size()) {
            activePageIndex = 0;
        }
        return pages.get(activePageIndex);
    }

    public static LayoutModel fromJsonString(String jsonStr) {
        try {
            JSONObject root = new JSONObject(jsonStr);
            LayoutModel l = new LayoutModel();
            l.name = root.optString("name", "Layout");
            l.author = root.optString("author", "AirMIDI");
            l.version = root.optString("version", "1.0");
            l.canvasWidth = (float) root.optDouble("canvasWidth", 920.0);
            l.canvasHeight = (float) root.optDouble("canvasHeight", 460.0);

            l.pages.clear();
            JSONArray pagesArr = root.optJSONArray("pages");
            if (pagesArr != null && pagesArr.length() > 0) {
                for (int i = 0; i < pagesArr.length(); i++) {
                    JSONObject pObj = pagesArr.optJSONObject(i);
                    if (pObj != null) {
                        l.pages.add(PageModel.fromJson(pObj));
                    }
                }
            }

            if (l.pages.isEmpty()) {
                // Fallback for single-page legacy layout
                PageModel defaultPage = new PageModel();
                defaultPage.id = "page_1";
                defaultPage.name = "Screen 1";
                JSONArray arr = root.optJSONArray("controls");
                if (arr != null) {
                    for (int i = 0; i < arr.length(); i++) {
                        JSONObject cObj = arr.optJSONObject(i);
                        if (cObj != null) {
                            defaultPage.controls.add(ControlModel.fromJson(cObj));
                        }
                    }
                }
                l.pages.add(defaultPage);
            }

            int reqIdx = root.optInt("activePageIndex", 0);
            if (reqIdx < 0 || reqIdx >= l.pages.size()) {
                reqIdx = 0;
            }
            l.activePageIndex = reqIdx;
            l.controls = l.pages.get(reqIdx).controls;

            return l;
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public static LayoutModel loadFromAsset(Context ctx, String assetName) {
        try {
            InputStream is = ctx.getAssets().open(assetName);
            int size = is.available();
            byte[] buffer = new byte[size];
            is.read(buffer);
            is.close();
            String json = new String(buffer, StandardCharsets.UTF_8);
            return fromJsonString(json);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public static LayoutModel loadFromFile(java.io.File file) {
        try {
            java.io.FileInputStream fis = new java.io.FileInputStream(file);
            int size = (int) file.length();
            byte[] buffer = new byte[size];
            fis.read(buffer);
            fis.close();
            String json = new String(buffer, StandardCharsets.UTF_8);
            return fromJsonString(json);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public static final String ACTIVE_STATE_FILE = "active_layout_state.json";

    public static boolean saveLayoutState(Context ctx, LayoutModel layout) {
        if (ctx == null || layout == null) return false;
        try {
            java.io.File dir = ctx.getFilesDir();
            java.io.File tempFile = new java.io.File(dir, ACTIVE_STATE_FILE + ".tmp");
            java.io.File targetFile = new java.io.File(dir, ACTIVE_STATE_FILE);
            String json = layout.toJsonString();
            java.io.FileOutputStream fos = new java.io.FileOutputStream(tempFile);
            fos.write(json.getBytes(StandardCharsets.UTF_8));
            fos.flush();
            fos.close();
            return tempFile.renameTo(targetFile);
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public static LayoutModel loadActiveLayoutState(Context ctx) {
        if (ctx == null) return null;
        try {
            java.io.File file = new java.io.File(ctx.getFilesDir(), ACTIVE_STATE_FILE);
            if (!file.exists()) return null;
            return loadFromFile(file);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public String toJsonString() {
        try {
            JSONObject root = new JSONObject();
            root.put("name", name != null ? name : "Layout");
            root.put("author", author != null ? author : "AirMIDI");
            root.put("version", version != null ? version : "1.0");
            root.put("canvasWidth", canvasWidth);
            root.put("canvasHeight", canvasHeight);
            root.put("activePageIndex", activePageIndex);

            JSONArray pArr = new JSONArray();
            if (pages != null) {
                for (PageModel p : pages) {
                    pArr.put(p.toJson());
                }
            }
            root.put("pages", pArr);

            // Backward compatibility
            JSONArray arr = new JSONArray();
            if (controls != null) {
                for (ControlModel c : controls) {
                    arr.put(c.toJson());
                }
            }
            root.put("controls", arr);

            return root.toString();
        } catch (Exception e) {
            return "{}";
        }
    }
}
