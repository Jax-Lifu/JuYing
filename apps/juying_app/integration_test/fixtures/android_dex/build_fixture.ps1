param(
    [string]$Sdk = 'D:/Android/Sdk',
    [string]$GradleCache = "$env:USERPROFILE/.gradle/caches/modules-2/files-2.1",
    [string]$Output = "$env:TEMP/juying-android-dex-fixture"
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot/../../..").Path
$androidJar = "$Sdk/platforms/android-34/android.jar"
$libraries = @(
    Get-ChildItem "$GradleCache/com.squareup.okhttp3/okhttp/4.12.0" -Filter 'okhttp-4.12.0.jar' -Recurse
    Get-ChildItem "$GradleCache/org.jetbrains.kotlin/kotlin-stdlib" -Filter 'kotlin-stdlib-*.jar' -Recurse |
        Where-Object { $_.Name -notmatch '(sources|javadoc)' } | Select-Object -First 1
)
$classpath = (@($androidJar) + $libraries.FullName) -join ';'
$classes = New-Item -ItemType Directory -Force "$Output/classes"

& javac -encoding UTF-8 -source 8 -target 8 -classpath $classpath -d $classes.FullName `
    "$repoRoot/android/app/src/main/java/com/github/catvod/crawler/Spider.java" `
    "$repoRoot/android/app/src/main/java/com/github/catvod/net/OkHttp.java" `
    "$PSScriptRoot/Init.java" "$PSScriptRoot/Fixture.java"
if ($LASTEXITCODE -ne 0) { throw 'Fixture Java compilation failed' }

# Ship only fixture classes: the Spider ABI must be linked from the installed host APK.
& jar --create --file "$Output/fixture-classes.jar" -C $classes.FullName com/github/catvod/spider
if ($LASTEXITCODE -ne 0) { throw 'Fixture class packaging failed' }
& "$Sdk/build-tools/36.0.0/d8.bat" --release --min-api 24 --lib $androidJar `
    --classpath $classes.FullName --output "$Output/fixture.jar" "$Output/fixture-classes.jar"
if ($LASTEXITCODE -ne 0) { throw 'Fixture Dex compilation failed' }

# The same local clip exercises native playback and AAC output without public CDN variability.
& ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=25:duration=8' `
    -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$Output/media.mp4"
if ($LASTEXITCODE -ne 0) { throw 'Fixture video generation failed' }
& ffmpeg -hide_banner -loglevel error -y -i "$Output/media.mp4" `
    -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=8' `
    -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 128k -ac 2 `
    -shortest -movflags +faststart "$Output/audio.mp4"
if ($LASTEXITCODE -ne 0) { throw 'Fixture AAC generation failed' }
Get-FileHash -Algorithm SHA256 "$Output/fixture.jar"
