#!/usr/bin/env bash
# Builds one app from the template with every library in gradle/libs.versions.toml and every skill's
# example code, as the skills tell an agent to set them up. If it builds, the catalog's versions work
# together with this toolchain and every example compiles. Run it before a release that changes the
# template or the skills:
#   ./skills-check.sh [work dir]          (default: $CACHE/skillcheck)
# It needs an installed engine's template (gradle wrapper, local.properties, gradle.properties): the one
# bin/paths.sh finds, or HATCHLYBOX_HOME and HATCHLYBOX_CACHE pointing at it.
set -euo pipefail
cd "$(dirname "$0")"
src=$PWD
source bin/paths.sh
mkdir -p "$CACHE"
exec 6> "$CACHE/work.lock"
flock -n 6 || { echo "another job is running" >&2; exit 1; }
data=$DATA
w=${1:-$CACHE/skillcheck}
pkg=com.hatchlybox.skillcheck

rm -rf "$w"
mkdir -p "$w" && cp -r "$data/template/." "$w/"
# The template as this checkout has it (the installed one may be older), placeholders filled in.
cp -r template/. "$w/"
cp "$data/template/local.properties" "$data/template/gradle.properties" "$w/"
grep -rl '__PKG__\|__NAME__\|__LABEL__' "$w" | xargs sed -i "s/__PKG__/$pkg/g; s/__NAME__/skillcheck/g; s/__LABEL__/Skill check/g"
j=$w/app/src/main/java
mkdir -p "$j/${pkg//.//}"
mv "$j/com/hatchlybox/template/MainActivity.kt" "$j/${pkg//.//}/"
rmdir -p "$j/com/hatchlybox/template" 2>/dev/null || true

# Every plugin and library the skills use.
sed -i 's|^    alias(libs.plugins.kotlin.compose)$|&\n    alias(libs.plugins.ksp)\n    alias(libs.plugins.kotlin.serialization)|' "$w/app/build.gradle.kts"
sed -i 's|^    // More, tested with this toolchain:.*$|    implementation(libs.androidx.lifecycle.runtime.compose)\n    implementation(libs.androidx.navigation.compose)\n    implementation(libs.androidx.room.runtime)\n    implementation(libs.androidx.room.ktx)\n    ksp(libs.androidx.room.compiler)\n    implementation(libs.androidx.datastore.preferences)\n    implementation(libs.androidx.work.runtime.ktx)\n    implementation(libs.kotlinx.coroutines.android)\n    implementation(libs.kotlinx.serialization.json)\n    implementation(libs.ktor.client.android)\n    implementation(libs.ktor.client.content.negotiation)\n    implementation(libs.ktor.serialization.kotlinx.json)\n    implementation(libs.coil.compose)\n    implementation(libs.androidx.camera.camera2)\n    implementation(libs.androidx.camera.lifecycle)\n    implementation(libs.androidx.camera.view)\n    implementation(libs.androidx.media3.exoplayer)\n    implementation(libs.androidx.media3.ui)\n    implementation(libs.androidx.glance.appwidget)\n    implementation(libs.androidx.glance.material3)|' "$w/app/build.gradle.kts"
grep -q 'glance.material3' "$w/app/build.gradle.kts" || { echo "couldn't add the libraries to app/build.gradle.kts" >&2; exit 1; }

# Every skill's example code and resources, in its own package.
for d in skills/*/example; do
  s=$(basename "$(dirname "$d")")
  mkdir -p "$j/skill/$s"
  cp "$d"/*.kt "$j/skill/$s/" 2>/dev/null || true
  [ -d "$d/res" ] && cp -r "$d/res/." "$w/app/src/main/res/"
done

# The manifest entries the skills ask for.
sed -i 's|^<manifest xmlns:android="http://schemas.android.com/apk/res/android">$|&\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.CAMERA" />\n    <uses-feature android:name="android.hardware.camera" android:required="false" />|' "$w/app/src/main/AndroidManifest.xml"
sed -i 's|^    </application>$|        <receiver android:name="skill.widget.HomeWidgetReceiver" android:exported="true">\n            <intent-filter>\n                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />\n            </intent-filter>\n            <meta-data android:name="android.appwidget.provider" android:resource="@xml/skill_widget_info" />\n        </receiver>\n&|' "$w/app/src/main/AndroidManifest.xml"

# A main activity that uses one screen from every skill, so nothing is left unchecked.
cat > "$j/${pkg//.//}/MainActivity.kt" <<EOF
package $pkg

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import skill.camera.CameraScreen
import skill.data.ItemsScreen
import skill.design.AppTheme
import skill.design.EmptyState
import skill.design.SectionHeader
import skill.games.BallGame
import skill.media.AudioPlayer
import skill.network.JokeScreen
import skill.reminders.Notifications
import skill.reminders.RemindersScreen
import skill.screens.ScreensApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Notifications.createChannel(this)
        val tabs = listOf("screens", "data", "remind", "net", "game", "camera", "media", "design")
        setContent {
            AppTheme {
                var tab by rememberSaveable { mutableIntStateOf(0) }
                Scaffold(topBar = {
                    TabRow(selectedTabIndex = tab) { tabs.forEachIndexed { i, t -> Tab(selected = tab == i, onClick = { tab = i }, text = { Text(t) }) } }
                }) { inner ->
                    val m = Modifier.fillMaxSize().padding(inner)
                    when (tab) {
                        0 -> Column(m) { ScreensApp() }
                        1 -> ItemsScreen(modifier = m)
                        2 -> RemindersScreen(m)
                        3 -> JokeScreen(modifier = m)
                        4 -> BallGame(m)
                        5 -> CameraScreen(m)
                        6 -> Column(m) { AudioPlayer("https://upload.wikimedia.org/wikipedia/commons/c/c8/Example.ogg", "Example sound") }
                        else -> Column(m.verticalScroll(rememberScrollState())) {
                            SectionHeader("Empty state")
                            EmptyState("Nothing here yet", "Add the first one", onAction = {})
                        }
                    }
                }
            }
        }
    }
}
EOF

echo "== building $w (every library, every skill example)"
cd "$w"
if HATCHLYBOX_HOME="$src" "$src/bin/isolate" build "$w" timeout 30m ./gradlew --console=plain -q assembleRelease; then
  apk=$(ls app/build/outputs/apk/release/*.apk | head -1)
  echo "== OK: everything builds ($(du -h "$apk" | cut -f1) APK)"
else
  echo "== FAILED: see the errors above" >&2
  exit 1
fi
