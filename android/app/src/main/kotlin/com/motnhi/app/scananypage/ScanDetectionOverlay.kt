package com.motnhi.app.scananypage

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.View

/** The detected reading region, in PreviewView coordinates; never intercepts the shutter. */
internal class ScanDetectionOverlay(context: Context) : View(context) {
    private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 3f * resources.displayMetrics.density
    }
    private var region: RectF? = null

    fun show(bounds: RectF?, readable: Boolean) {
        region = bounds?.let(::RectF)
        outline.color = if (readable) 0xFF81C995.toInt() else 0xFFFFCA28.toInt()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        region?.let { canvas.drawRoundRect(it, 8f, 8f, outline) }
    }
}
