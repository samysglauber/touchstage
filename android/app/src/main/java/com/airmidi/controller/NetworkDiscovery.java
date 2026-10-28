package com.airmidi.controller;

import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class NetworkDiscovery {

    public static class DiscoveredDevice {
        public String name;
        public String host;
        public int port;
        public long lastSeen;

        public DiscoveredDevice(String name, String host, int port) {
            this.name = name;
            this.host = host;
            this.port = port;
            this.lastSeen = System.currentTimeMillis();
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            DiscoveredDevice that = (DiscoveredDevice) o;
            return host.equals(that.host) && port == that.port;
        }

        @Override
        public int hashCode() {
            return host.hashCode() + port;
        }
    }

    public interface DiscoveryListener {
        void onDevicesUpdated(List<DiscoveredDevice> devices);
    }

    private static final int BEACON_PORT = 9002;
    private final List<DiscoveredDevice> deviceList = Collections.synchronizedList(new ArrayList<>());
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private DatagramSocket socket;
    private volatile boolean isRunning = false;
    private DiscoveryListener listener;

    public NetworkDiscovery(DiscoveryListener listener) {
        this.listener = listener;
    }

    public void start() {
        if (isRunning) return;
        isRunning = true;

        executor.execute(() -> {
            try {
                socket = new DatagramSocket(null);
                socket.setReuseAddress(true);
                socket.setBroadcast(true);
                socket.bind(new InetSocketAddress(BEACON_PORT));

                byte[] buffer = new byte[1024];
                while (isRunning) {
                    DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                    socket.receive(packet);

                    String text = new String(packet.getData(), 0, packet.getLength(), StandardCharsets.UTF_8);
                    try {
                        JSONObject json = new JSONObject(text);
                        String service = json.optString("service");
                        if ("touchstage".equalsIgnoreCase(service) || "airmidi".equalsIgnoreCase(service)) {
                            String name = json.optString("name", "TouchStage Bridge");
                            String host = json.optString("host", packet.getAddress().getHostAddress());
                            int port = json.optInt("port", 9000);

                            DiscoveredDevice dev = new DiscoveredDevice(name, host, port);
                            addOrUpdateDevice(dev);
                        }
                    } catch (Exception ignored) {}
                }
            } catch (Exception e) {
                // Socket closed or error
            } finally {
                stop();
            }
        });
    }

    private void addOrUpdateDevice(DiscoveredDevice dev) {
        synchronized (deviceList) {
            int idx = deviceList.indexOf(dev);
            if (idx >= 0) {
                deviceList.get(idx).lastSeen = System.currentTimeMillis();
                deviceList.get(idx).name = dev.name;
            } else {
                deviceList.add(dev);
            }
            // Remove devices not seen in last 10 seconds
            long now = System.currentTimeMillis();
            deviceList.removeIf(d -> (now - d.lastSeen) > 10000);
        }

        mainHandler.post(() -> {
            if (listener != null) {
                synchronized (deviceList) {
                    listener.onDevicesUpdated(new ArrayList<>(deviceList));
                }
            }
        });
    }

    public List<DiscoveredDevice> getDevices() {
        synchronized (deviceList) {
            return new ArrayList<>(deviceList);
        }
    }

    public void stop() {
        isRunning = false;
        if (socket != null && !socket.isClosed()) {
            try {
                socket.close();
            } catch (Exception ignored) {}
        }
        socket = null;
    }
}
