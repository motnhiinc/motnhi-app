package com.motnhi.app.scananypage

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Four corners of a page, normalized to the sampled scan-guide area. */
internal data class PagePoint(val x: Float, val y: Float)
internal data class PageQuad(
    val topLeft: PagePoint,
    val topRight: PagePoint,
    val bottomRight: PagePoint,
    val bottomLeft: PagePoint,
) {
    fun corners() = listOf(topLeft, topRight, bottomRight, bottomLeft)
}

/** Conservative high-contrast page-edge detector. Uncertain edges require manual capture. */
internal object PageBoundaryDetector {
    private data class Edge(val intercept: Float, val slope: Float, val score: Float)
    private data class Evidence(val coverage: Float, val contrast: Float) {
        val score get() = coverage * 0.7f + contrast * 0.3f
    }

    fun detect(gray: IntArray, width: Int, height: Int): PageQuad? {
        require(width > 20 && height > 20 && gray.size == width * height)
        val left = candidates(gray, width, height, vertical = true, first = true)
        val right = candidates(gray, width, height, vertical = true, first = false)
        val top = candidates(gray, width, height, vertical = false, first = true)
        val bottom = candidates(gray, width, height, vertical = false, first = false)
        if (listOf(left, right, top, bottom).any { it.isEmpty() }) return null
        var best: PageQuad? = null
        var bestScore = 0f
        for (l in left) for (r in right) for (t in top) for (b in bottom) {
            val tl = intersect(l, t) ?: continue
            val tr = intersect(r, t) ?: continue
            val br = intersect(r, b) ?: continue
            val bl = intersect(l, b) ?: continue
            val quad = PageQuad(tl, tr, br, bl)
            if (quad.corners().any { it.x !in 0.025f..0.975f || it.y !in 0.025f..0.975f }) continue
            val xSpan = ((tr.x - tl.x) + (br.x - bl.x)) / 2
            val ySpan = ((bl.y - tl.y) + (br.y - tr.y)) / 2
            if (xSpan < 0.4f || ySpan < 0.4f || xSpan * ySpan < 0.27f ||
                xSpan / ySpan !in 0.45f..2.1f) continue
            val leftEvidence = evidence(gray, width, height, l, true, tl.y, bl.y)
            val rightEvidence = evidence(gray, width, height, r, true, tr.y, br.y)
            val topEvidence = evidence(gray, width, height, t, false, tl.x, tr.x)
            val bottomEvidence = evidence(gray, width, height, b, false, bl.x, br.x)
            val edges = listOf(leftEvidence, rightEvidence, topEvidence, bottomEvidence)
            if (edges.any { it.coverage < 0.6f || it.contrast < 0.2f }) continue
            val score = edges.sumOf { it.score.toDouble() }.toFloat() / 4 +
                xSpan * ySpan * 0.12f
            if (score > bestScore) { best = quad; bestScore = score }
        }
        return best
    }

    private fun candidates(gray: IntArray, width: Int, height: Int, vertical: Boolean, first: Boolean): List<Edge> {
        val extent = if (vertical) width else height
        val minPos = if (first) 0.06f else 0.51f
        val maxPos = if (first) 0.49f else 0.94f
        val found = ArrayList<Edge>()
        val step = max(1, extent / 100)
        for (pixel in (minPos * extent).toInt()..(maxPos * extent).toInt() step step) {
            val intercept = pixel.toFloat() / extent
            for (slopeIndex in -5..5) {
                val slope = slopeIndex * 0.04f
                val edge = Edge(intercept, slope, 0f)
                val sample = evidence(gray, width, height, edge, vertical, 0.28f, 0.72f)
                if (sample.coverage < 0.55f || sample.contrast < 0.22f) continue
                found.add(edge.copy(score = sample.score))
            }
        }
        return found.sortedByDescending { it.score }.fold(mutableListOf<Edge>()) { selected, edge ->
            if (selected.size < 5 && selected.none {
                    abs(it.intercept - edge.intercept) < 0.045f && abs(it.slope - edge.slope) < 0.08f
                }) selected.add(edge)
            selected
        }
    }

    private fun evidence(
        gray: IntArray, width: Int, height: Int, edge: Edge, vertical: Boolean,
        start: Float, end: Float,
    ): Evidence {
        if (end <= start) return Evidence(0f, 0f)
        var hits = 0
        var contrast = 0f
        val samples = 24
        for (i in 0 until samples) {
            val along = start + (end - start) * (i + 0.5f) / samples
            val across = edge.intercept + edge.slope * (along - 0.5f)
            val x = (if (vertical) across * width else along * width).toInt()
            val y = (if (vertical) along * height else across * height).toInt()
            if (x < 3 || y < 3 || x >= width - 3 || y >= height - 3) continue
            val difference = if (vertical) abs(gray[y * width + x - 2] - gray[y * width + x + 2])
                else abs(gray[(y - 2) * width + x] - gray[(y + 2) * width + x])
            if (difference >= 28) {
                hits++
                contrast += min(difference, 120) / 120f
            }
        }
        return Evidence(hits.toFloat() / samples, contrast / samples)
    }

    private fun intersect(vertical: Edge, horizontal: Edge): PagePoint? {
        // x = vx + vs(y - .5); y = hy + hs(x - .5)
        val denominator = 1 - vertical.slope * horizontal.slope
        if (abs(denominator) < 0.5f) return null
        val x = (vertical.intercept - vertical.slope * 0.5f +
            vertical.slope * (horizontal.intercept - horizontal.slope * 0.5f)) / denominator
        val y = horizontal.intercept + horizontal.slope * (x - 0.5f)
        return if (x.isFinite() && y.isFinite()) PagePoint(x, y) else null
    }
}
