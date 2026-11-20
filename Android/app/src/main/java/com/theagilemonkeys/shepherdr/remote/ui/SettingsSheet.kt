package com.theagilemonkeys.shepherdr.remote.ui

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.theagilemonkeys.shepherdr.remote.dictation.Dictation
import com.theagilemonkeys.shepherdr.remote.relay.RelayClient

/** Paired Macs, dictation's language and pairing another Mac. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(client: RelayClient, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("shepherdr", Context.MODE_PRIVATE) }
    var locale by remember { mutableStateOf(prefs.getString(Dictation.LOCALE_KEY, "") ?: "") }
    var pairing by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = Theme.panel) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp).navigationBarsPadding()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Settings", style = Theme.mono(16f, FontWeight.SemiBold), color = Theme.text)
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Done", color = Theme.phosphor) }
            }
            SectionTitle("Macs")
            for (mac in client.macs) {
                Row(
                    Modifier.fillMaxWidth().clickable { client.select(mac); onDismiss() }.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(mac.name, style = Theme.mono(14f), color = Theme.text)
                        Text(mac.hosts.joinToString(" · ") { "$it:${mac.port}" }, style = Theme.mono(10f), color = Theme.dim)
                    }
                    if (client.mac?.id == mac.id) Icon(Icons.Filled.Check, contentDescription = "Current", tint = Theme.phosphor)
                    Spacer(Modifier.width(8.dp))
                    TextButton(onClick = { client.forget(mac) }) { Text("Forget", color = Theme.red) }
                }
            }
            TextButton(onClick = { pairing = true }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                Text("Pair Another Mac…", color = Theme.phosphor)
            }
            SectionTitle("Dictation language")
            for ((tag, name) in listOf("" to "Same as the phone", "es-ES" to "Español (España)", "en-US" to "English (US)", "en-GB" to "English (UK)")) {
                Row(
                    Modifier.fillMaxWidth().clickable {
                        locale = tag
                        prefs.edit().putString(Dictation.LOCALE_KEY, tag).apply()
                    },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = locale == tag, onClick = null,
                        colors = RadioButtonDefaults.colors(selectedColor = Theme.phosphor, unselectedColor = Theme.dim),
                        modifier = Modifier.padding(10.dp),
                    )
                    Text(name, style = Theme.mono(13f), color = Theme.text)
                }
            }
            Text(
                "Your phone transcribes with Android's speech recognition, on the device when it can. " +
                    "You may need to download the language in the phone's speech settings first.",
                style = Theme.mono(11f), color = Theme.dim, modifier = Modifier.padding(top = 6.dp),
            )
        }
    }
    if (pairing) {
        Dialog(onDismissRequest = { pairing = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            PairScreen(client, onPaired = { pairing = false; onDismiss() })
        }
    }
}
