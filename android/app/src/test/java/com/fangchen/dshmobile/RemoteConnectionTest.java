package com.fangchen.dshmobile;

import org.junit.Test;

import static org.junit.Assert.*;

public final class RemoteConnectionTest {
    @Test public void parsesDesktopPairingUrl() {
        RemoteConnection connection = RemoteConnection.parse(
                "http://192.168.1.8:3081/__remote/pair?token=0123456789abcdef"
        );
        assertNotNull(connection);
        assertEquals("http://192.168.1.8:3081/", connection.baseUrl);
        assertEquals("http://192.168.1.8:3081/__remote/api/status", connection.statusUrl());
        assertEquals("http://192.168.1.8:3081/__remote/api/action", connection.actionUrl());
        assertEquals("0123456789abcdef", connection.token);
    }

    @Test public void rejectsInvalidPairingUrls() {
        assertNull(RemoteConnection.parse("http://mac.local:3081/__remote/pair?token=short"));
        assertNull(RemoteConnection.parse("http://mac.local:3081/not-pairing?token=0123456789abcdef"));
        assertNull(RemoteConnection.parse("file:///__remote/pair?token=0123456789abcdef"));
    }

    @Test public void decodesEscapedToken() {
        RemoteConnection connection = RemoteConnection.parse(
                "https://mac.example/__remote/pair?token=0123456789abcdef%2Bvalue"
        );
        assertNotNull(connection);
        assertEquals("0123456789abcdef+value", connection.token);
    }
}

