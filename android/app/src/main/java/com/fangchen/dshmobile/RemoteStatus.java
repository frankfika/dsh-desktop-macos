package com.fangchen.dshmobile;

import org.json.JSONObject;

public final class RemoteStatus {
    public final String state;
    public final String label;
    public final String detail;
    public final boolean controllable;

    private RemoteStatus(String state, String label, String detail, boolean controllable) {
        this.state = state;
        this.label = label;
        this.detail = detail;
        this.controllable = controllable;
    }

    public boolean isReady() {
        return "running".equals(state) || "externalRunning".equals(state);
    }

    public static RemoteStatus fromJson(String json) throws Exception {
        JSONObject object = new JSONObject(json);
        return new RemoteStatus(
                object.getString("state"),
                object.optString("label", object.getString("state")),
                object.optString("detail", ""),
                object.optBoolean("controllable", false)
        );
    }
}

