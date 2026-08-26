package com.fangchen.dshmobile;

import android.os.Handler;
import android.os.Looper;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class RemoteClient {
    public interface Callback<T> {
        void complete(T value, Exception error);
    }

    private final ExecutorService statusExecutor = Executors.newSingleThreadExecutor();
    private final ExecutorService actionExecutor = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    public void status(RemoteConnection connection, Callback<RemoteStatus> callback) {
        statusExecutor.execute(() -> {
            try {
                HttpURLConnection request = open(connection.statusUrl(), connection);
                String body = read(request);
                RemoteStatus status = RemoteStatus.fromJson(body);
                main.post(() -> callback.complete(status, null));
            } catch (Exception error) {
                main.post(() -> callback.complete(null, error));
            }
        });
    }

    public void action(RemoteConnection connection, String action, Callback<Void> callback) {
        actionExecutor.execute(() -> {
            try {
                HttpURLConnection request = open(connection.actionUrl(), connection);
                request.setRequestMethod("POST");
                request.setRequestProperty("Content-Type", "application/json");
                request.setDoOutput(true);
                byte[] body = new JSONObject().put("action", action).toString().getBytes(StandardCharsets.UTF_8);
                request.getOutputStream().write(body);
                read(request);
                main.post(() -> callback.complete(null, null));
            } catch (Exception error) {
                main.post(() -> callback.complete(null, error));
            }
        });
    }

    public void close() {
        statusExecutor.shutdownNow();
        actionExecutor.shutdownNow();
    }

    private HttpURLConnection open(String url, RemoteConnection connection) throws Exception {
        HttpURLConnection request = (HttpURLConnection) new URL(url).openConnection();
        request.setConnectTimeout(5000);
        request.setReadTimeout(5000);
        request.setUseCaches(false);
        request.setInstanceFollowRedirects(false);
        request.setRequestProperty("Cookie", "dsh_remote_session=" + connection.token);
        return request;
    }

    private String read(HttpURLConnection request) throws Exception {
        int code = request.getResponseCode();
        InputStream stream = code >= 200 && code < 300 ? request.getInputStream() : request.getErrorStream();
        if (code < 200 || code >= 300) throw new IllegalStateException("HTTP " + code);
        StringBuilder result = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) result.append(line);
        } finally {
            request.disconnect();
        }
        return result.toString();
    }
}
