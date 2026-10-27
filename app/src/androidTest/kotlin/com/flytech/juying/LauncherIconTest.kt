package com.flytech.juying

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.AdaptiveIconDrawable
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LauncherIconTest {
    @Test fun packagedIconAndBannerRenderAtLauncherSizes() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val icon = context.packageManager.getApplicationIcon(context.packageName) as AdaptiveIconDrawable
        val foreground = context.getDrawable(R.drawable.ic_launcher_foreground)!!
        val safeArea = Bitmap.createBitmap(108, 108, Bitmap.Config.ARGB_8888)
        foreground.setBounds(0, 0, 108, 108)
        foreground.draw(Canvas(safeArea))
        for (y in 0 until 108) for (x in 0 until 108) {
            if (Color.alpha(safeArea.getPixel(x, y)) > 0) {
                assertTrue("Logo must fit the adaptive icon safe circle", kotlin.math.hypot(x - 53.5, y - 53.5) <= 33.5)
            }
        }
        safeArea.recycle()
        val bitmap = Bitmap.createBitmap(720, 440, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.rgb(32, 34, 39))
        icon.setBounds(30, 30, 310, 310)
        icon.draw(canvas)
        val small = context.packageManager.getApplicationIcon(context.packageName)
        small.setBounds(350, 44, 398, 92)
        small.draw(canvas)
        val tiny = context.packageManager.getApplicationIcon(context.packageName)
        tiny.setBounds(420, 52, 452, 84)
        tiny.draw(canvas)
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            val mono = icon.monochrome
            assertNotNull(mono)
            canvas.drawCircle(530f, 68f, 28f, Paint().apply { color = Color.rgb(233, 174, 99) })
            mono!!.setTint(Color.rgb(16, 17, 21))
            mono.setBounds(488, 26, 572, 110)
            mono.draw(canvas)
        }
        val banner = context.getDrawable(R.drawable.banner)!!
        banner.setBounds(350, 130, 670, 310)
        banner.draw(canvas)
        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 20f }
        canvas.drawText("Adaptive icon", 30f, 350f, label)
        canvas.drawText("48 / 32 px + themed", 350f, 350f, label)
        canvas.drawText("TV banner 320 x 180", 350f, 385f, label)
        File(context.getExternalFilesDir(null), "launcher-preview.png").outputStream().use {
            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
        bitmap.recycle()
    }
}
