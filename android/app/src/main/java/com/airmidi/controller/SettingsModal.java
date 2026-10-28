package com.airmidi.controller;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.util.List;

public class SettingsModal {

    public interface SettingsListener {
        void onDeviceSelected(String host, int port);
        void onPresetSelected(PresetManager.PresetItem presetItem);
        void onDeviceNameChanged(String newName);
        void onSidebarPositionChanged(String landscapePos, String portraitPos);
    }

    private final Context context;
    private final SettingsListener listener;
    private Dialog dialog;
    private LinearLayout devicesContainer;
    private TextView searchingText;
    private String currentConnectedHost = "";
    private String currentLandscapePos = "right";
    private String currentPortraitPos = "bottom";

    public SettingsModal(Context context, SettingsListener listener) {
        this.context = context;
        this.listener = listener;
    }

    public void setConnectedHost(String host) {
        this.currentConnectedHost = host != null ? host.trim() : "";
    }

    public void setSidebarPositions(String landscapePos, String portraitPos) {
        if (landscapePos != null) this.currentLandscapePos = landscapePos;
        if (portraitPos != null) this.currentPortraitPos = portraitPos;
    }

    public void show(List<NetworkDiscovery.DiscoveredDevice> initialDevices, String currentDeviceName) {
        show(initialDevices, currentDeviceName, currentLandscapePos, currentPortraitPos);
    }

    public void show(List<NetworkDiscovery.DiscoveredDevice> initialDevices, String currentDeviceName, String landscapePos, String portraitPos) {
        if (landscapePos != null) this.currentLandscapePos = landscapePos;
        if (portraitPos != null) this.currentPortraitPos = portraitPos;

        dialog = new Dialog(context);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        if (dialog.getWindow() != null) {
            dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        }

        // Apple-style Dark Card Container
        LinearLayout root = new LinearLayout(context);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(20), dp(20), dp(24));

        GradientDrawable bg = new GradientDrawable();
        bg.setShape(GradientDrawable.RECTANGLE);
        bg.setCornerRadius(dp(16));
        bg.setColor(Color.parseColor("#1C1C1E"));
        bg.setStroke(dp(1), Color.parseColor("#2C2C2E"));
        root.setBackground(bg);

        // Header: "Settings" and "Done" button
        LinearLayout header = new LinearLayout(context);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        TextView title = new TextView(context);
        title.setText("Settings");
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0f);
        header.addView(title, titleParams);

        TextView doneBtn = new TextView(context);
        doneBtn.setText("Done");
        doneBtn.setTextColor(Color.parseColor("#0A84FF")); // Apple system blue
        doneBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        doneBtn.setTypeface(Typeface.DEFAULT_BOLD);
        doneBtn.setPadding(dp(12), dp(6), dp(6), dp(6));
        doneBtn.setOnClickListener(v -> dialog.dismiss());
        header.addView(doneBtn);

        root.addView(header);

        // Scrollable content
        ScrollView scroll = new ScrollView(context);
        scroll.setVerticalScrollBarEnabled(false);
        LinearLayout content = new LinearLayout(context);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, dp(16), 0, 0);

        // -------------------------------------------------------------
        // SECTION 1: DISCOVERED BRIDGES
        // -------------------------------------------------------------
        content.addView(createSectionHeader("AVAILABLE BRIDGES"));

        devicesContainer = new LinearLayout(context);
        devicesContainer.setOrientation(LinearLayout.VERTICAL);
        content.addView(devicesContainer);

        searchingText = new TextView(context);
        searchingText.setText("Searching local network for AirMIDI Bridge...");
        searchingText.setTextColor(Color.parseColor("#8E8E93"));
        searchingText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        searchingText.setPadding(0, dp(8), 0, dp(12));
        content.addView(searchingText);

        updateDevices(initialDevices);

        // Manual IP option
        TextView manualToggle = new TextView(context);
        manualToggle.setText("Connect via Manual IP");
        manualToggle.setTextColor(Color.parseColor("#0A84FF"));
        manualToggle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        manualToggle.setPadding(0, dp(6), 0, dp(16));

        LinearLayout manualContainer = new LinearLayout(context);
        manualContainer.setOrientation(LinearLayout.HORIZONTAL);
        manualContainer.setVisibility(View.GONE);
        manualContainer.setPadding(0, 0, 0, dp(16));

        EditText ipInput = new EditText(context);
        ipInput.setHint("10.0.0.124");
        ipInput.setHintTextColor(Color.parseColor("#636366"));
        ipInput.setTextColor(Color.WHITE);
        ipInput.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        ipInput.setBackground(createFieldBackground());
        ipInput.setPadding(dp(12), dp(10), dp(12), dp(10));
        LinearLayout.LayoutParams ipParams = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0f);
        ipParams.rightMargin = dp(8);
        manualContainer.addView(ipInput, ipParams);

        TextView connectBtn = new TextView(context);
        connectBtn.setText("Connect");
        connectBtn.setTextColor(Color.WHITE);
        connectBtn.setTypeface(Typeface.DEFAULT_BOLD);
        connectBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        connectBtn.setPadding(dp(16), dp(10), dp(16), dp(10));
        connectBtn.setBackground(createButtonBackground(Color.parseColor("#0A84FF")));
        connectBtn.setOnClickListener(v -> {
            String ip = ipInput.getText().toString().trim();
            if (!ip.isEmpty()) {
                if (listener != null) listener.onDeviceSelected(ip, 9000);
                dialog.dismiss();
            }
        });
        manualContainer.addView(connectBtn);

        manualToggle.setOnClickListener(v -> {
            manualContainer.setVisibility(manualContainer.getVisibility() == View.VISIBLE ? View.GONE : View.VISIBLE);
        });
        content.addView(manualToggle);
        content.addView(manualContainer);

        // -------------------------------------------------------------
        // SECTION 2: PRESETS (BUILT-IN & CUSTOM USER PRESETS)
        // -------------------------------------------------------------
        content.addView(createSectionHeader("LAYOUT PRESETS"));

        LinearLayout presetsContainer = new LinearLayout(context);
        presetsContainer.setOrientation(LinearLayout.VERTICAL);
        content.addView(presetsContainer);
        populatePresets(presetsContainer);

        // -------------------------------------------------------------
        // SECTION 3: SIDEBAR POSITION
        // -------------------------------------------------------------
        content.addView(createSectionHeader("SIDEBAR POSITION"));

        View landscapeRow = createSegmentedRow(
            "Landscape Sidebar",
            new String[]{ "Right (Default)", "Left" },
            new String[]{ "right", "left" },
            currentLandscapePos,
            newVal -> {
                currentLandscapePos = newVal;
                if (listener != null) {
                    listener.onSidebarPositionChanged(currentLandscapePos, currentPortraitPos);
                }
            }
        );
        content.addView(landscapeRow);

        View portraitRow = createSegmentedRow(
            "Portrait Control Bar",
            new String[]{ "Bottom (Default)", "Top" },
            new String[]{ "bottom", "top" },
            currentPortraitPos,
            newVal -> {
                currentPortraitPos = newVal;
                if (listener != null) {
                    listener.onSidebarPositionChanged(currentLandscapePos, currentPortraitPos);
                }
            }
        );
        content.addView(portraitRow);

        // -------------------------------------------------------------
        // SECTION 4: DEVICE IDENTITY
        // -------------------------------------------------------------
        content.addView(createSectionHeader("DEVICE IDENTITY"));

        EditText nameInput = new EditText(context);
        nameInput.setText(currentDeviceName != null ? currentDeviceName : "Phone");
        nameInput.setTextColor(Color.WHITE);
        nameInput.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        nameInput.setBackground(createFieldBackground());
        nameInput.setPadding(dp(12), dp(10), dp(12), dp(10));
        nameInput.addTextChangedListener(new android.text.TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
            @Override
            public void afterTextChanged(android.text.Editable s) {
                if (listener != null && s != null) {
                    listener.onDeviceNameChanged(s.toString().trim());
                }
            }
        });
        nameInput.setOnFocusChangeListener((v, hasFocus) -> {
            if (!hasFocus) {
                if (listener != null) listener.onDeviceNameChanged(nameInput.getText().toString().trim());
            }
        });
        content.addView(nameInput);

        scroll.addView(content);
        root.addView(scroll);

        dialog.setContentView(root);

        // Fit width to 85% of screen
        int width = (int) (context.getResources().getDisplayMetrics().widthPixels * 0.85f);
        int maxWidth = dp(480);
        if (width > maxWidth) width = maxWidth;
        dialog.getWindow().setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);

        dialog.setOnDismissListener(d -> {
            if (listener != null && nameInput.getText() != null) {
                listener.onDeviceNameChanged(nameInput.getText().toString().trim());
            }
            if (context instanceof MainActivity) {
                ((MainActivity) context).hideSystemUI();
            }
        });

        dialog.show();
    }

    private void populatePresets(LinearLayout container) {
        container.removeAllViews();
        List<PresetManager.PresetItem> presets = PresetManager.getAllPresets(context);
        for (PresetManager.PresetItem item : presets) {
            container.addView(createPresetRow(item, () -> populatePresets(container)));
        }
    }

    public void updateDevices(List<NetworkDiscovery.DiscoveredDevice> devices) {
        if (devicesContainer == null) return;
        devicesContainer.removeAllViews();

        if (devices == null || devices.isEmpty()) {
            if (searchingText != null) {
                searchingText.setText("Searching local network for AirMIDI Bridge...");
                searchingText.setVisibility(View.VISIBLE);
            }
            return;
        }

        if (searchingText != null) {
            searchingText.setVisibility(View.GONE);
        }

        for (NetworkDiscovery.DiscoveredDevice d : devices) {
            boolean isCurrent = d.host.equals(currentConnectedHost);
            devicesContainer.addView(createDeviceRow(d, isCurrent));
        }
    }

    private View createDeviceRow(NetworkDiscovery.DiscoveredDevice dev, boolean isConnected) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        row.setBackground(createCellBackground());

        LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        );
        rowParams.bottomMargin = dp(6);
        row.setLayoutParams(rowParams);

        LinearLayout textCol = new LinearLayout(context);
        textCol.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams colParams = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0f);
        textCol.setLayoutParams(colParams);

        TextView nameText = new TextView(context);
        nameText.setText(dev.name);
        nameText.setTextColor(Color.WHITE);
        nameText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        nameText.setTypeface(Typeface.DEFAULT_BOLD);
        textCol.addView(nameText);

        TextView subText = new TextView(context);
        subText.setText(dev.host + ":" + dev.port);
        subText.setTextColor(Color.parseColor("#8E8E93"));
        subText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        textCol.addView(subText);

        row.addView(textCol);

        TextView actionText = new TextView(context);
        if (isConnected) {
            actionText.setText("Connected");
            actionText.setTextColor(Color.parseColor("#30D158")); // Apple system green
        } else {
            actionText.setText("Connect");
            actionText.setTextColor(Color.parseColor("#0A84FF")); // Apple system blue
        }
        actionText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        actionText.setTypeface(Typeface.DEFAULT_BOLD);
        row.addView(actionText);

        row.setOnClickListener(v -> {
            if (listener != null) {
                listener.onDeviceSelected(dev.host, dev.port);
            }
            if (dialog != null) dialog.dismiss();
        });

        return row;
    }

    private View createPresetRow(PresetManager.PresetItem item, Runnable onListChanged) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        row.setBackground(createCellBackground());

        LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        );
        rowParams.bottomMargin = dp(6);
        row.setLayoutParams(rowParams);

        LinearLayout textCol = new LinearLayout(context);
        textCol.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams colParams = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0f);
        textCol.setLayoutParams(colParams);

        TextView text = new TextView(context);
        text.setText(item.name);
        text.setTextColor(Color.WHITE);
        text.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        textCol.addView(text);

        TextView tagText = new TextView(context);
        tagText.setText(item.isCustom ? "Saved on Device" : "Default");
        tagText.setTextColor(Color.parseColor("#8E8E93"));
        tagText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        textCol.addView(tagText);

        row.addView(textCol);

        if (item.isCustom) {
            TextView delBtn = new TextView(context);
            delBtn.setText("Delete");
            delBtn.setTextColor(Color.parseColor("#FF453A"));
            delBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
            delBtn.setPadding(dp(6), dp(4), dp(10), dp(4));
            delBtn.setOnClickListener(v -> {
                PresetManager.deletePreset(item);
                if (onListChanged != null) onListChanged.run();
            });
            row.addView(delBtn);
        }

        TextView arrow = new TextView(context);
        arrow.setText("Load");
        arrow.setTextColor(Color.parseColor("#0A84FF"));
        arrow.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        arrow.setTypeface(Typeface.DEFAULT_BOLD);
        arrow.setPadding(dp(4), dp(4), dp(4), dp(4));
        row.addView(arrow);

        row.setOnClickListener(v -> {
            if (listener != null) {
                listener.onPresetSelected(item);
            }
            if (dialog != null) dialog.dismiss();
        });

        return row;
    }

    private interface OptionSelectListener {
        void onSelected(String value);
    }

    private View createSegmentedRow(String label, String[] titles, String[] values, String selectedValue, OptionSelectListener onSelect) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        row.setBackground(createCellBackground());

        LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        );
        rowParams.bottomMargin = dp(8);
        row.setLayoutParams(rowParams);

        TextView labelView = new TextView(context);
        labelView.setText(label);
        labelView.setTextColor(Color.WHITE);
        labelView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        labelView.setTypeface(Typeface.DEFAULT_BOLD);
        row.addView(labelView);

        // Segmented bar
        LinearLayout segContainer = new LinearLayout(context);
        segContainer.setOrientation(LinearLayout.HORIZONTAL);
        segContainer.setPadding(dp(3), dp(3), dp(3), dp(3));
        GradientDrawable segBg = new GradientDrawable();
        segBg.setShape(GradientDrawable.RECTANGLE);
        segBg.setCornerRadius(dp(8));
        segBg.setColor(Color.parseColor("#1C1C1E"));
        segContainer.setBackground(segBg);

        LinearLayout.LayoutParams segParams = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        );
        segParams.topMargin = dp(8);
        segContainer.setLayoutParams(segParams);

        final TextView[] segmentViews = new TextView[titles.length];
        final String[] curValHolder = new String[]{ selectedValue };

        for (int i = 0; i < titles.length; i++) {
            final String val = values[i];
            TextView seg = new TextView(context);
            seg.setText(titles[i]);
            seg.setGravity(Gravity.CENTER);
            seg.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
            seg.setPadding(dp(8), dp(8), dp(8), dp(8));
            LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0f);
            seg.setLayoutParams(p);

            segmentViews[i] = seg;
            updateSegmentView(seg, val.equalsIgnoreCase(curValHolder[0]));

            seg.setOnClickListener(v -> {
                curValHolder[0] = val;
                for (int j = 0; j < titles.length; j++) {
                    updateSegmentView(segmentViews[j], values[j].equalsIgnoreCase(curValHolder[0]));
                }
                if (onSelect != null) {
                    onSelect.onSelected(val);
                }
            });

            segContainer.addView(seg);
        }

        row.addView(segContainer);
        return row;
    }

    private void updateSegmentView(TextView seg, boolean isSelected) {
        if (isSelected) {
            GradientDrawable d = new GradientDrawable();
            d.setShape(GradientDrawable.RECTANGLE);
            d.setCornerRadius(dp(6));
            d.setColor(Color.parseColor("#0A84FF")); // Apple blue
            seg.setBackground(d);
            seg.setTextColor(Color.WHITE);
            seg.setTypeface(Typeface.DEFAULT_BOLD);
        } else {
            seg.setBackground(null);
            seg.setTextColor(Color.parseColor("#8E8E93"));
            seg.setTypeface(Typeface.DEFAULT);
        }
    }

    private TextView createSectionHeader(String text) {
        TextView tv = new TextView(context);
        tv.setText(text);
        tv.setTextColor(Color.parseColor("#8E8E93"));
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        tv.setPadding(0, dp(14), 0, dp(6));
        return tv;
    }

    private GradientDrawable createCellBackground() {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setCornerRadius(dp(10));
        d.setColor(Color.parseColor("#2C2C2E"));
        return d;
    }

    private GradientDrawable createFieldBackground() {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setCornerRadius(dp(8));
        d.setColor(Color.parseColor("#2C2C2E"));
        d.setStroke(dp(1), Color.parseColor("#3A3A3C"));
        return d;
    }

    private GradientDrawable createButtonBackground(int color) {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setCornerRadius(dp(8));
        d.setColor(color);
        return d;
    }

    private int dp(float value) {
        return (int) TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value, context.getResources().getDisplayMetrics()
        );
    }
}
