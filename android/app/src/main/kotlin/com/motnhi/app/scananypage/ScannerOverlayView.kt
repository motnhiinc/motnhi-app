package com.motnhi.app.scananypage

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

internal enum class ScannerGuidance { FindPage, HoldStill, Preparing }

/** Scanner-local presentation using the same paper, ink, fonts, and dock as the AR reader. */
internal class ScannerOverlayView(context: Context, onBack: () -> Unit, onCapture: () -> Unit) : FrameLayout(context) {
    private val paper = Color.rgb(255, 250, 244)
    private val ink = Color.rgb(32, 26, 24)
    private val muted = Color.rgb(116, 107, 102)
    private val line = Color.rgb(219, 208, 196)
    private val sage = Color.rgb(59, 100, 76)
    private val coral = Color.rgb(220, 112, 75)
    private val sans = font("NunitoSans-Regular", Typeface.NORMAL)
    private val bold = font("NunitoSans-ExtraBold", Typeface.BOLD)
    private val serif = font("SourceSerif4-SemiBold", Typeface.NORMAL)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val maskPath = Path()
    private val topBar = LinearLayout(context)
    private val back = TextView(context)
    private val badge = TextView(context)
    private val dock = ScrollView(context)
    private val caption = TextView(context)
    private val body = TextView(context)
    private val captureButton = TextView(context)
    private var guidance = ScannerGuidance.FindPage
    private var reservedDockHeight = 0
    private var measuredViewportWidth = 0
    private var measuredViewportHeight = 0
    private var frame = RectF()
    var onGuideChanged: (() -> Unit)? = null

    val guideRect: RectF get() = RectF(frame)

    init {
        setWillNotDraw(false)
        topBar.orientation = LinearLayout.HORIZONTAL
        topBar.gravity = Gravity.CENTER_VERTICAL
        back.apply {
            text = label("Back", "Quay lại")
            typeface = bold
            textSize = 16f
            setTextColor(ink)
            gravity = Gravity.CENTER
            minHeight = dp(52)
            setPadding(dp(18), dp(12), dp(18), dp(12))
            compoundDrawablePadding = dp(8)
            val arrow = ScannerSymbol(ink, false).apply { setBounds(0, 0, dp(20), dp(20)) }
            setCompoundDrawablesRelative(arrow, null, null, null)
            background = RippleDrawable(ColorStateList.valueOf(0x24DC704B), rounded(paper, 28f), null)
            elevation = dp(4).toFloat()
            contentDescription = text
            setOnClickListener { onBack() }
        }
        topBar.addView(back, LinearLayout.LayoutParams(-2, -2))
        topBar.addView(View(context), LinearLayout.LayoutParams(0, 1, 1f))
        badge.apply {
            text = label("SCAN A PAGE", "QUÉT TRANG SÁCH")
            typeface = bold
            textSize = 12f
            letterSpacing = 0.06f
            setTextColor(paper)
            gravity = Gravity.CENTER
            minHeight = dp(44)
            setPadding(dp(14), dp(10), dp(14), dp(10))
            compoundDrawablePadding = dp(8)
            val document = ScannerSymbol(paper, true).apply { setBounds(0, 0, dp(18), dp(18)) }
            setCompoundDrawablesRelative(document, null, null, null)
            background = rounded(0xD9201A18.toInt(), 24f, false)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        topBar.addView(badge, LinearLayout.LayoutParams(-2, -2))
        addView(topBar)

        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(18))
        }
        caption.apply {
            typeface = bold
            textSize = 12f
            letterSpacing = 0.08f
            setTextColor(sage)
            includeFontPadding = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        content.addView(caption, LinearLayout.LayoutParams(-1, -2))
        val title = TextView(context).apply {
            text = label("Scan a page", "Quét trang sách")
            typeface = serif
            textSize = 24f
            setTextColor(ink)
            includeFontPadding = false
            setLineSpacing(dp(2).toFloat(), 1f)
        }
        content.addView(title, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        body.apply {
            typeface = sans
            textSize = 15f
            setTextColor(muted)
            includeFontPadding = false
            minLines = 2
            setLineSpacing(dp(3).toFloat(), 1f)
            accessibilityLiveRegion = ACCESSIBILITY_LIVE_REGION_POLITE
        }
        content.addView(body, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        captureButton.apply {
            text = label("Capture page", "Chụp trang này")
            typeface = bold
            textSize = 16f
            setTextColor(ink)
            gravity = Gravity.CENTER
            minHeight = dp(56)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), rounded(coral, 28f, false), null)
            setOnClickListener { onCapture() }
        }
        content.addView(captureButton, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
        dock.apply {
            isVerticalScrollBarEnabled = false
            background = rounded(paper, 24f)
            clipToOutline = true
            elevation = dp(8).toFloat()
            if (Build.VERSION.SDK_INT >= 28) {
                outlineAmbientShadowColor = 0x404C392B
                outlineSpotShadowColor = 0x404C392B
            }
            addView(content, FrameLayout.LayoutParams(-1, -2))
        }
        addView(dock)
        renderGuidance()
    }

    fun setGuidance(value: ScannerGuidance) {
        if (guidance == value) return
        guidance = value
        renderGuidance()
        invalidate()
    }

    fun setCaptureEnabled(enabled: Boolean) {
        captureButton.isEnabled = enabled
        captureButton.alpha = if (enabled) 1f else 0.55f
    }

    private fun renderGuidance() {
        caption.text = when (guidance) {
            ScannerGuidance.FindPage -> label("AUTOMATIC CAPTURE", "TỰ ĐỘNG CHỤP")
            ScannerGuidance.HoldStill -> label("PAGE FOUND", "ĐÃ TÌM THẤY TRANG")
            ScannerGuidance.Preparing -> label("GETTING READY", "ĐANG CHUẨN BỊ")
        }
        body.text = when (guidance) {
            ScannerGuidance.FindPage -> label("Fit one page in the frame, or tap Capture.", "Đưa một trang vào khung, hoặc bấm Chụp trang này.")
            ScannerGuidance.HoldStill -> label("Page edges found. Hold still for auto capture.", "Đã tìm thấy viền trang. Giữ yên để tự chụp.")
            ScannerGuidance.Preparing -> label("Page captured. Getting your character ready to read.", "Đã chụp trang sách. Đang chuẩn bị nhân vật để đọc.")
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = MeasureSpec.getSize(heightMeasureSpec)
        if (w != measuredViewportWidth || h != measuredViewportHeight) {
            reservedDockHeight = 0
            measuredViewportWidth = w
            measuredViewportHeight = h
        }
        val availableWidth = max(1, w - paddingLeft - paddingRight - dp(32))
        val availableHeight = max(1, h - paddingTop - paddingBottom)
        val unspecified = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        back.measure(unspecified, unspecified)
        badge.measure(unspecified, unspecified)
        badge.visibility = if (resources.configuration.fontScale >= 1.5f ||
            back.measuredWidth + badge.measuredWidth + dp(16) > availableWidth) GONE else VISIBLE
        topBar.measure(MeasureSpec.makeMeasureSpec(availableWidth, MeasureSpec.EXACTLY), unspecified)
        val landscape = availableWidth > availableHeight && availableWidth >= dp(480)
        val dockWidth = if (landscape) min(dp(320), (availableWidth * 0.42f).toInt()) else min(dp(640), availableWidth)
        val maxDockHeight = max(1, if (landscape) availableHeight - topBar.measuredHeight - dp(48)
            else min((availableHeight * 0.4f).toInt(), availableHeight - topBar.measuredHeight - dp(96)))
        dock.minimumHeight = min(reservedDockHeight, maxDockHeight)
        dock.measure(MeasureSpec.makeMeasureSpec(dockWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(maxDockHeight, MeasureSpec.AT_MOST))
        // Retain enough space for the longest state label. A shorter "Hold
        // still" label must not keep moving the guide and resetting capture.
        reservedDockHeight = max(reservedDockHeight, dock.measuredHeight)
        setMeasuredDimension(w, h)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val headerLeft = paddingLeft + dp(16)
        val headerTop = paddingTop + dp(16)
        topBar.layout(headerLeft, headerTop, headerLeft + topBar.measuredWidth, headerTop + topBar.measuredHeight)
        val availableWidth = width - paddingLeft - paddingRight
        val availableHeight = height - paddingTop - paddingBottom
        val landscape = availableWidth - dp(32) > availableHeight && availableWidth - dp(32) >= dp(480)
        val dockLeft = if (landscape) width - paddingRight - dp(16) - dock.measuredWidth
            else paddingLeft + (availableWidth - dock.measuredWidth) / 2
        val dockBottom = height - paddingBottom - dp(24)
        dock.layout(dockLeft, dockBottom - dock.measuredHeight, dockLeft + dock.measuredWidth, dockBottom)
        val areaLeft = paddingLeft + dp(24).toFloat()
        val areaTop = topBar.bottom + dp(24).toFloat()
        val areaRight = if (landscape) dockLeft - dp(24).toFloat() else width - paddingRight - dp(24).toFloat()
        val areaBottom = if (landscape) height - paddingBottom - dp(24).toFloat()
            else dockBottom - reservedDockHeight - dp(24).toFloat()
        val areaWidth = max(0f, areaRight - areaLeft)
        val areaHeight = max(0f, areaBottom - areaTop)
        val frameWidth = min(areaWidth, areaHeight * 0.74f)
        val frameHeight = frameWidth / 0.74f
        val x = areaLeft + (areaWidth - frameWidth) / 2
        val y = areaTop + (areaHeight - frameHeight) / 2
        val next = RectF(x, y, x + frameWidth, y + frameHeight)
        if (next != frame) {
            frame = next
            onGuideChanged?.invoke()
        }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        paint.style = Paint.Style.FILL
        paint.shader = null
        paint.color = 0x48000000
        maskPath.reset()
        maskPath.fillType = Path.FillType.EVEN_ODD
        maskPath.addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
        maskPath.addRoundRect(frame, dp(22).toFloat(), dp(22).toFloat(), Path.Direction.CW)
        canvas.drawPath(maskPath, paint)
        paint.shader = LinearGradient(0f, 0f, 0f, dp(180).toFloat(),
            0x60000000, Color.TRANSPARENT, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, width.toFloat(), dp(180).toFloat(), paint)
        paint.shader = null
        if (frame.isEmpty) return
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = dp(2).toFloat()
        paint.color = if (guidance == ScannerGuidance.HoldStill) 0xFFBFEDCD.toInt() else 0xCCFFFAF4.toInt()
        canvas.drawRoundRect(frame, dp(22).toFloat(), dp(22).toFloat(), paint)
        paint.color = if (guidance == ScannerGuidance.HoldStill) 0xFFBFEDCD.toInt() else coral
        paint.strokeWidth = dp(4).toFloat()
        paint.strokeCap = Paint.Cap.ROUND
        val corner = min(dp(44).toFloat(), min(frame.width(), frame.height()))
        canvas.drawArc(frame.left, frame.top, frame.left + corner, frame.top + corner, 180f, 90f, false, paint)
        canvas.drawArc(frame.right - corner, frame.top, frame.right, frame.top + corner, 270f, 90f, false, paint)
        canvas.drawArc(frame.right - corner, frame.bottom - corner, frame.right, frame.bottom, 0f, 90f, false, paint)
        canvas.drawArc(frame.left, frame.bottom - corner, frame.left + corner, frame.bottom, 90f, 90f, false, paint)
        paint.strokeCap = Paint.Cap.BUTT
    }

    private fun rounded(color: Int, radius: Float, border: Boolean = true) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius.toInt()).toFloat()
        if (border) setStroke(dp(1), line)
    }
    private fun font(asset: String, fallbackStyle: Int): Typeface = try {
        Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/$asset.ttf")
    } catch (_: RuntimeException) { Typeface.create(Typeface.DEFAULT, fallbackStyle) }
    private fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
    private fun label(en: String, vi: String) = if (Locale.getDefault().language == "vi") vi else en
}

private class ScannerSymbol(color: Int, private val document: Boolean) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        style = Paint.Style.STROKE
        strokeWidth = 2f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    override fun draw(canvas: Canvas) {
        val saved = canvas.save()
        canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
        canvas.scale(bounds.width() / 24f, bounds.height() / 24f)
        if (document) {
            canvas.drawRoundRect(5f, 3f, 19f, 21f, 2f, 2f, paint)
            canvas.drawLine(9f, 8f, 15f, 8f, paint)
            canvas.drawLine(9f, 12f, 15f, 12f, paint)
            canvas.drawLine(9f, 16f, 13f, 16f, paint)
        } else {
            canvas.drawLine(19f, 12f, 5f, 12f, paint)
            canvas.drawLine(11f, 6f, 5f, 12f, paint)
            canvas.drawLine(5f, 12f, 11f, 18f, paint)
        }
        canvas.restoreToCount(saved)
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha; invalidateSelf() }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter; invalidateSelf() }
    @Deprecated("Deprecated in Android")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
