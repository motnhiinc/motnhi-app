package com.motnhi.app.scananypage

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ScanPageImageTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()

    private fun image(width: Int, height: Int, orientation: Int = ExifInterface.ORIENTATION_NORMAL): ScanPageImage {
        val file = File.createTempFile("scan-fixture", ".jpg", context.cacheDir)
        try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            for (y in 0 until height / 2) for (x in 0 until width / 2) bitmap.setPixel(x, y, Color.RED)
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }
            bitmap.recycle()
            ExifInterface(file).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
                saveAttributes()
            }
            return ScanPageImage.fromUri(context, Uri.fromFile(file))
        } finally { file.delete() }
    }

    @Test fun exactLongestEdgeAndNoUpscaling() {
        for ((source, target) in listOf(4000 to 3000, 6000 to 3000, 2048 to 2048)) {
            val page = image(source, source / 2)
            assertEquals(target, page.bitmap.width)
            assertEquals(target / 2, page.bitmap.height)
            assertTrue(page.jpeg.isNotEmpty())
            assertTrue(page.jpeg.size <= 8 * 1024 * 1024)
            page.bitmap.recycle()
        }
    }

    @Test fun exifRotationAndMirrorShareFinalCoordinates() {
        val rotated = image(80, 40, ExifInterface.ORIENTATION_ROTATE_90)
        assertEquals(40, rotated.bitmap.width)
        assertEquals(80, rotated.bitmap.height)
        assertTrue(Color.red(rotated.bitmap.getPixel(30, 10)) > 200)
        assertTrue(Color.green(rotated.bitmap.getPixel(30, 10)) < 50)
        rotated.bitmap.recycle()
        val mirrored = image(80, 40, ExifInterface.ORIENTATION_FLIP_HORIZONTAL)
        assertTrue(Color.green(mirrored.bitmap.getPixel(70, 10)) < 50)
        assertTrue(Color.green(mirrored.bitmap.getPixel(10, 10)) > 200)
        mirrored.bitmap.recycle()
    }

    @Test fun decodeFailureIsNotRecognitionFailure() {
        val file = File.createTempFile("invalid-scan", ".jpg", context.cacheDir)
        try {
            file.writeText("not an image")
            try { ScanPageImage.fromUri(context, Uri.fromFile(file)); fail("must reject") }
            catch (error: IllegalArgumentException) { assertEquals("image_decode_failed", error.message) }
        } finally { file.delete() }
    }

    @Test fun allExifOrientationsPreserveCornerGeometry() {
        // Red source quadrant is top-left; each expected corner is in final space.
        val expectedCorners = listOf(1 to (0 to 0), 2 to (1 to 0), 3 to (1 to 1), 4 to (0 to 1),
            5 to (0 to 0), 6 to (1 to 0), 7 to (1 to 1), 8 to (0 to 1))
        for ((orientation, corner) in expectedCorners) {
            val page = image(80, 40, orientation)
            assertEquals(if (orientation >= 5) 40 else 80, page.bitmap.width)
            assertEquals(if (orientation >= 5) 80 else 40, page.bitmap.height)
            val x = if (corner.first == 0) 5 else page.bitmap.width - 6
            val y = if (corner.second == 0) 5 else page.bitmap.height - 6
            val color = page.bitmap.getPixel(x, y)
            assertTrue("EXIF $orientation", Color.red(color) > 200 && Color.green(color) < 50)
            page.bitmap.recycle()
        }
    }

    @Test fun observationalQualityUsesTextNotIllustrationEdges() {
        val bitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.GRAY)
        val lines = listOf(RecognizedTextLine("chữ", TextLineBox(10, 10, 50, 30)))
        val before = PageQuality.assess(bitmap, lines)
        for (y in 60 until 100) for (x in 60 until 100) bitmap.setPixel(x, y, if ((x + y) % 2 == 0) Color.WHITE else Color.BLACK)
        val after = PageQuality.assess(bitmap, lines)
        assertEquals(before["sharpness"], after["sharpness"])
        assertEquals("observational", after["mode"])
        assertFalse(PageQuality.assess(bitmap, emptyList()).containsKey("sharpness"))
        bitmap.recycle()
    }
}
