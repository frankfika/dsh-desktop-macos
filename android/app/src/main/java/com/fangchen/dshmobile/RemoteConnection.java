package com.fangchen.dshmobile;

import org.json.JSONException;
import org.json.JSONObject;

import java.net.URI;
import java.net.URLDecoder;

public final class RemoteConnection {
    public final String name;
    public final String baseUrl;
    public final String token;

    public RemoteConnection(String name, String baseUrl, String token) {
        this.name = name;
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl : baseUrl + "/";
        this.token = token;
    }

    public String statusUrl() { return baseUrl + "__remote/api/status"; }
    public String actionUrl() { return baseUrl + "__remote/api/action"; }

    public static RemoteConnection parse(String value) {
        try {
            URI uri = URI.create(value.trim());
            if (!("http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) ||
                    uri.getHost() == null || !"/__remote/pair".equals(uri.getPath())) return null;
            String token = queryValue(uri.getRawQuery(), "token");
            if (token == null || token.length() < 16) return null;
            URI base = new URI(uri.getScheme(), null, uri.getHost(), uri.getPort(), "/", null, null);
            return new RemoteConnection("我的电脑", base.toString(), token);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String queryValue(String query, String key) {
        if (query == null) return null;
        for (String pair : query.split("&")) {
            int index = pair.indexOf('=');
            String name = decode(index < 0 ? pair : pair.substring(0, index));
            if (key.equals(name)) {
                return decode(index < 0 ? "" : pair.substring(index + 1));
            }
        }
        return null;
    }

    private static String decode(String value) {
        try { return URLDecoder.decode(value, "UTF-8"); }
        catch (Exception ignored) { return value; }
    }

    public JSONObject toJson() throws JSONException {
        return new JSONObject().put("name", name).put("baseUrl", baseUrl).put("token", token);
    }

    public static RemoteConnection fromJson(String json) throws JSONException {
        JSONObject object = new JSONObject(json);
        return new RemoteConnection(object.getString("name"), object.getString("baseUrl"), object.getString("token"));
    }
}
