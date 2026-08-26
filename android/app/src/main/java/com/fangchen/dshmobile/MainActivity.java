package com.fangchen.dshmobile;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner;
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning;

import java.net.URI;

public final class MainActivity extends Activity {
    private final Handler pollHandler = new Handler(Looper.getMainLooper());
    private final RemoteClient client = new RemoteClient();
    private final Runnable pollTask = new Runnable() {
        @Override public void run() {
            refreshStatus();
        }
    };
    private boolean polling;
    private boolean statusRequestInFlight;

    private SecureStore store;
    private RemoteConnection connection;
    private RemoteStatus status;
    private TextView statusDot;
    private TextView statusTitle;
    private TextView statusDetail;
    private Button startButton;
    private Button restartButton;
    private Button stopButton;
    private Button harnessButton;

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        store = new SecureStore(this);
        connection = store.load();
        render();
    }

    @Override protected void onResume() {
        super.onResume();
        polling = true;
        pollHandler.removeCallbacks(pollTask);
        if (connection != null) pollHandler.post(pollTask);
    }

    @Override protected void onPause() {
        polling = false;
        pollHandler.removeCallbacks(pollTask);
        super.onPause();
    }

    @Override protected void onDestroy() {
        client.close();
        super.onDestroy();
    }

    private void render() {
        if (connection == null) renderPairing(); else renderDashboard();
    }

    private void renderPairing() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(color(R.color.background));
        LinearLayout content = column(24);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(dp(24), dp(56), dp(24), dp(32));

        TextView mark = text("DS", 22, Color.WHITE, true);
        mark.setGravity(Gravity.CENTER);
        mark.setBackgroundResource(R.drawable.card_background);
        content.addView(mark, size(dp(78), dp(78)));
        content.addView(spacer(30));

        TextView title = text("连接 DSH Desktop", 30, Color.WHITE, true);
        title.setGravity(Gravity.CENTER);
        content.addView(title, matchWrap());
        TextView subtitle = text("在电脑端点击「手机」，然后扫描配对二维码。", 16, color(R.color.text_secondary), false);
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setPadding(0, dp(10), 0, dp(28));
        content.addView(subtitle, matchWrap());

        Button scan = primaryButton("▣  扫描电脑二维码");
        scan.setContentDescription("扫描电脑二维码");
        scan.setOnClickListener(v -> scanPairingCode());
        content.addView(scan, size(ViewGroup.LayoutParams.MATCH_PARENT, dp(56)));

        TextView divider = text("或粘贴配对链接", 13, color(R.color.text_secondary), false);
        divider.setGravity(Gravity.CENTER);
        divider.setPadding(0, dp(26), 0, dp(10));
        content.addView(divider, matchWrap());

        EditText input = new EditText(this);
        input.setHint("http://电脑地址:3081/__remote/pair?token=…");
        input.setHintTextColor(color(R.color.text_secondary));
        input.setTextColor(Color.WHITE);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        input.setBackgroundResource(R.drawable.card_background);
        input.setPadding(dp(16), 0, dp(16), 0);
        content.addView(input, size(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)));

        Button connect = secondaryButton("连接");
        LinearLayout.LayoutParams connectParams = size(ViewGroup.LayoutParams.MATCH_PARENT, dp(52));
        connectParams.topMargin = dp(10);
        content.addView(connect, connectParams);
        connect.setOnClickListener(v -> acceptPairing(input.getText().toString()));

        TextView privacy = text("配对密钥使用 Android Keystore 加密保存在本机", 12, color(R.color.text_secondary), false);
        privacy.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams privacyParams = matchWrap();
        privacyParams.topMargin = dp(34);
        content.addView(privacy, privacyParams);

        scroll.addView(content);
        setContentView(scroll);
    }

    private void scanPairingCode() {
        GmsBarcodeScannerOptions options = new GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .enableAutoZoom()
                .build();
        GmsBarcodeScanner scanner = GmsBarcodeScanning.getClient(this, options);
        scanner.startScan()
                .addOnSuccessListener(code -> acceptPairing(code.getRawValue()))
                .addOnFailureListener(error -> Toast.makeText(this, "扫码失败，请粘贴配对链接", Toast.LENGTH_LONG).show());
    }

    private void acceptPairing(String value) {
        if (value == null) return;
        RemoteConnection candidate = RemoteConnection.parse(value);
        if (candidate == null) {
            Toast.makeText(this, "这不是有效的 DSH Desktop 配对链接", Toast.LENGTH_LONG).show();
            return;
        }
        try {
            store.save(candidate);
            connection = candidate;
            status = null;
            renderDashboard();
            pollHandler.removeCallbacks(pollTask);
            pollHandler.post(pollTask);
        } catch (Exception error) {
            Toast.makeText(this, "无法安全保存配对信息", Toast.LENGTH_LONG).show();
        }
    }

    private void renderDashboard() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(color(R.color.background));
        LinearLayout content = column(18);
        content.setPadding(dp(20), dp(36), dp(20), dp(30));

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout titleBlock = column(2);
        titleBlock.addView(text("DSH DESKTOP", 11, color(R.color.text_secondary), true), matchWrap());
        titleBlock.addView(text(connection.name, 30, Color.WHITE, true), matchWrap());
        header.addView(titleBlock, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        Button menu = secondaryButton("⋯");
        menu.setContentDescription("电脑设置");
        menu.setTextSize(24);
        menu.setOnClickListener(v -> confirmDisconnect());
        header.addView(menu, size(dp(52), dp(48)));
        content.addView(header, matchWrap());

        LinearLayout card = column(8);
        card.setBackgroundResource(R.drawable.card_background);
        LinearLayout stateLine = new LinearLayout(this);
        stateLine.setGravity(Gravity.CENTER_VERTICAL);
        statusDot = text("●", 18, color(R.color.warning), true);
        statusTitle = text("正在连接…", 24, Color.WHITE, true);
        statusTitle.setPadding(dp(10), 0, 0, 0);
        stateLine.addView(statusDot, wrapWrap());
        stateLine.addView(statusTitle, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        card.addView(stateLine, matchWrap());
        statusDetail = text(hostLabel(), 13, color(R.color.text_secondary), false);
        statusDetail.setTypeface(Typeface.MONOSPACE);
        card.addView(statusDetail, matchWrap());
        LinearLayout.LayoutParams cardParams = matchWrap();
        cardParams.topMargin = dp(24);
        content.addView(card, cardParams);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER);
        startButton = actionButton("▶\n启动", "start");
        restartButton = actionButton("↻\n重启", "restart");
        stopButton = actionButton("■\n停止", "stop");
        stopButton.setTextColor(color(R.color.danger));
        addWeighted(actions, startButton, 0);
        addWeighted(actions, restartButton, 10);
        addWeighted(actions, stopButton, 10);
        content.addView(actions, matchWrap());

        harnessButton = primaryButton("打开完整 DeepSeek Harness   →");
        harnessButton.setContentDescription("打开完整 DeepSeek Harness");
        harnessButton.setOnClickListener(v -> startActivity(new Intent(this, WebActivity.class)));
        content.addView(harnessButton, size(ViewGroup.LayoutParams.MATCH_PARENT, dp(60)));

        TextView hint = text("每 2 秒自动同步电脑状态 · 下次打开无需重新配对", 12, color(R.color.text_secondary), false);
        hint.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams hintParams = matchWrap();
        hintParams.topMargin = dp(22);
        content.addView(hint, hintParams);

        scroll.addView(content);
        setContentView(scroll);
        applyStatus();
    }

    private void refreshStatus() {
        if (connection == null || statusRequestInFlight) return;
        RemoteConnection requestedConnection = connection;
        statusRequestInFlight = true;
        client.status(requestedConnection, (value, error) -> {
            statusRequestInFlight = false;
            if (connection != requestedConnection) return;
            status = error == null ? value : null;
            applyStatus();
            if (polling) pollHandler.postDelayed(pollTask, 2000);
        });
    }

    private void applyStatus() {
        if (statusTitle == null) return;
        if (status == null) {
            statusTitle.setText("电脑离线");
            statusDetail.setText("请确认电脑端已开启手机桥接");
            statusDot.setTextColor(color(R.color.danger));
            setControls(false, false, false);
            return;
        }
        statusTitle.setText(status.label);
        statusDetail.setText(status.detail.isEmpty() ? hostLabel() : status.detail);
        int dot = status.isReady() ? R.color.success : ("failed".equals(status.state) ? R.color.danger : R.color.warning);
        statusDot.setTextColor(color(dot));
        boolean canStart = "stopped".equals(status.state) || "failed".equals(status.state);
        setControls(canStart, status.controllable, status.isReady());
    }

    private void setControls(boolean canStart, boolean canControl, boolean ready) {
        startButton.setEnabled(canStart);
        restartButton.setEnabled(canControl);
        stopButton.setEnabled(canControl);
        harnessButton.setEnabled(ready);
    }

    private Button actionButton(String title, String action) {
        Button button = secondaryButton(title);
        button.setAllCaps(false);
        button.setGravity(Gravity.CENTER);
        button.setOnClickListener(v -> {
            setControls(false, false, status != null && status.isReady());
            client.action(connection, action, (unused, error) -> {
                if (error != null) Toast.makeText(this, "指令发送失败", Toast.LENGTH_SHORT).show();
                pollHandler.postDelayed(this::refreshStatus, 700);
            });
        });
        return button;
    }

    private void confirmDisconnect() {
        new AlertDialog.Builder(this)
                .setTitle("断开这台电脑？")
                .setMessage("配对密钥将从本机删除。")
                .setNegativeButton("取消", null)
                .setPositiveButton("断开", (dialog, which) -> {
                    pollHandler.removeCallbacks(pollTask);
                    store.clear();
                    connection = null;
                    status = null;
                    renderPairing();
                }).show();
    }

    private String hostLabel() {
        try { return URI.create(connection.baseUrl).getAuthority(); }
        catch (Exception ignored) { return connection.baseUrl; }
    }

    private LinearLayout column(int spacingDp) {
        LinearLayout view = new LinearLayout(this);
        view.setOrientation(LinearLayout.VERTICAL);
        view.setShowDividers(LinearLayout.SHOW_DIVIDER_MIDDLE);
        if (spacingDp > 0) {
            View divider = new View(this);
            divider.setLayoutParams(size(1, dp(spacingDp)));
            view.setDividerDrawable(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
            view.setDividerPadding(dp(spacingDp));
        }
        return view;
    }

    private TextView text(String value, int sp, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private Button primaryButton(String title) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextSize(16);
        button.setTextColor(color(R.color.on_primary));
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setAllCaps(false);
        button.setBackgroundResource(R.drawable.button_primary);
        return button;
    }

    private Button secondaryButton(String title) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextColor(Color.WHITE);
        button.setAllCaps(false);
        button.setBackgroundResource(R.drawable.button_secondary);
        return button;
    }

    private void addWeighted(LinearLayout parent, View child, int leftMargin) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(76), 1);
        params.leftMargin = dp(leftMargin);
        parent.addView(child, params);
    }

    private View spacer(int heightDp) {
        View view = new View(this);
        view.setLayoutParams(size(1, dp(heightDp)));
        return view;
    }

    private int color(int resource) { return getColor(resource); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private LinearLayout.LayoutParams size(int width, int height) { return new LinearLayout.LayoutParams(width, height); }
    private LinearLayout.LayoutParams wrapWrap() { return size(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT); }
    private LinearLayout.LayoutParams matchWrap() { return size(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT); }
}
