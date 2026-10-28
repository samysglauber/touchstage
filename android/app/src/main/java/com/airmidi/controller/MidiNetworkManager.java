package com.airmidi.controller;

import android.os.Handler;
import android.os.Looper;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MidiNetworkManager {
    public interface ConnectionListener {
        void onConnectionStateChanged(boolean connected, String statusText);
        void onLayoutReceived(LayoutModel layout);
        void onMidiActivity();
        void onMidiReceived(int status, int data1, int data2);
    }

    private String host;
    private int port;
    private Socket tcpSocket;
    private OutputStream tcpOut;
    private DatagramSocket udpSocket;
    private InetAddress serverAddress;
    private volatile boolean isConnected = false;
    private volatile boolean shouldAutoReconnect = true;
    private final ExecutorService executor = Executors.newCachedThreadPool();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private ConnectionListener listener;
    private String deviceName;

    public void setDeviceName(String name) {
        this.deviceName = name;
        if (isConnected && name != null && !name.trim().isEmpty()) {
            sendTcpLine("DEVICE:" + name.trim());
        }
    }

    public void sendTcpLine(String line) {
        executor.execute(() -> {
            try {
                if (tcpOut != null) {
                    byte[] data = (line.endsWith("\n") ? line : line + "\n").getBytes(StandardCharsets.UTF_8);
                    tcpOut.write(data);
                    tcpOut.flush();
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        });
    }

    public MidiNetworkManager(String host, int port, ConnectionListener listener) {
        this.host = host;
        this.port = port;
        this.listener = listener;
        try {
            this.udpSocket = new DatagramSocket();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public boolean isConnected() {
        return isConnected;
    }

    public String getHost() {
        return host;
    }

    public int getPort() {
        return port;
    }

    public void updateHost(String host, int port) {
        this.host = host;
        this.port = port;
        disconnect();
        shouldAutoReconnect = true;
        connect();
    }

    public void connect() {
        if (host == null || host.trim().isEmpty()) {
            notifyState(false, "Toque aqui para configurar o IP do Mac");
            return;
        }

        shouldAutoReconnect = true;
        executor.execute(() -> {
            try {
                notifyState(false, "Conectando ao Mac (" + host.trim() + ":" + port + ")...");
                serverAddress = InetAddress.getByName(host.trim());
                tcpSocket = new Socket(serverAddress, port);
                tcpSocket.setTcpNoDelay(true);
                tcpSocket.setSoTimeout(0); // keep alive
                tcpOut = tcpSocket.getOutputStream();
                isConnected = true;

                if (deviceName != null && !deviceName.trim().isEmpty()) {
                    byte[] dNameBytes = ("DEVICE:" + deviceName.trim() + "\n").getBytes(StandardCharsets.UTF_8);
                    tcpOut.write(dNameBytes);
                    tcpOut.flush();
                }

                notifyState(true, "Conectado ao Mac (" + host.trim() + ")");

                // Reader loop for layout synchronization & bidirectional MIDI from DAW
                BufferedReader reader = new BufferedReader(new InputStreamReader(tcpSocket.getInputStream(), StandardCharsets.UTF_8));
                String line;
                while (isConnected && (line = reader.readLine()) != null) {
                    line = line.trim();
                    if (line.startsWith("SYNC_LAYOUT:") || line.startsWith("LAYOUT:")) {
                        String json = line.startsWith("SYNC_LAYOUT:") ? line.substring(12) : line.substring(7);
                        LayoutModel updated = LayoutModel.fromJsonString(json);
                        if (updated != null) {
                            mainHandler.post(() -> {
                                if (listener != null) listener.onLayoutReceived(updated);
                            });
                        }
                    } else if (line.startsWith("MIDI:")) {
                        String[] parts = line.substring(5).split(",");
                        if (parts.length >= 3) {
                            try {
                                int st = Integer.parseInt(parts[0].trim(), 16);
                                int d1 = Integer.parseInt(parts[1].trim());
                                int d2 = Integer.parseInt(parts[2].trim());
                                mainHandler.post(() -> {
                                    if (listener != null) {
                                        listener.onMidiReceived(st, d1, d2);
                                    }
                                });
                            } catch (Exception ignored) {}
                        }
                    }
                }
            } catch (Exception e) {
                // Connection failed or lost
            } finally {
                boolean wasConnected = isConnected;
                isConnected = false;
                try {
                    if (tcpSocket != null) tcpSocket.close();
                } catch (Exception ignored) {}
                tcpSocket = null;
                tcpOut = null;

                notifyState(false, "Desconectado do Mac (Tentando reconectar...)");

                // Auto-reconnect after 3 seconds if not manually cancelled
                if (shouldAutoReconnect && host != null && !host.trim().isEmpty()) {
                    try {
                        Thread.sleep(3000);
                        if (shouldAutoReconnect && !isConnected) {
                            connect();
                        }
                    } catch (InterruptedException ignored) {}
                }
            }
        });
    }

    private void notifyState(boolean connected, String message) {
        mainHandler.post(() -> {
            if (listener != null) listener.onConnectionStateChanged(connected, message);
        });
    }

    public void disconnect() {
        shouldAutoReconnect = false;
        isConnected = false;
        try {
            if (tcpSocket != null) tcpSocket.close();
        } catch (Exception ignored) {}
        tcpSocket = null;
        tcpOut = null;
    }

    public void sendMidi(int status, int data1, int data2) {
        byte[] bytes = new byte[] {
            (byte) (status & 0xFF),
            (byte) (data1 & 0x7F),
            (byte) (data2 & 0x7F)
        };

        if (listener != null) {
            mainHandler.post(listener::onMidiActivity);
        }

        executor.execute(() -> {
            try {
                if (serverAddress != null && udpSocket != null) {
                    DatagramPacket packet = new DatagramPacket(bytes, 3, serverAddress, port);
                    udpSocket.send(packet);
                } else if (tcpOut != null) {
                    tcpOut.write(bytes);
                    tcpOut.flush();
                }
            } catch (Exception e) {
                try {
                    if (tcpOut != null) {
                        tcpOut.write(bytes);
                        tcpOut.flush();
                    }
                } catch (Exception ignored) {}
            }
        });
    }

    public void sendCC(int channel, int ccNumber, int value) {
        int ch = Math.max(0, Math.min(15, channel - 1));
        int status = 0xB0 | ch;
        sendMidi(status, ccNumber, value);
    }

    public void sendNoteOn(int channel, int noteNumber, int velocity) {
        int ch = Math.max(0, Math.min(15, channel - 1));
        int status = 0x90 | ch;
        sendMidi(status, noteNumber, velocity);
    }

    public void sendNoteOff(int channel, int noteNumber) {
        int ch = Math.max(0, Math.min(15, channel - 1));
        int status = 0x80 | ch;
        sendMidi(status, noteNumber, 0);
    }
}
