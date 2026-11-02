package com.motnhi.app.characterreader

import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test

class ReaderDepthSamplerTest {
    private val sampler = ReaderDepthSampler()

    private fun patch(values: List<Int>, rowStride: Int = 16, pixelStride: Int = 4): ByteBuffer {
        val buffer = ByteBuffer.allocate(3 * rowStride)
        values.forEachIndexed { index, mm ->
            val offset = index / 3 * rowStride + index % 3 * pixelStride
            buffer.put(offset, (mm and 255).toByte())
            buffer.put(offset + 1, (mm shr 8).toByte())
        }
        return buffer
    }

    @Test fun respectsStridesAndUnsignedLittleEndianSamples() {
        assertEquals(1.5f, sampler.samplePatch(patch(List(9) { 1500 }), 3, 3, 16, 4, 1, 1)!!, 0f)
    }

    @Test fun medianRejectsOutliersButRequiresFiveConsistentPixels() {
        assertEquals(1f, sampler.samplePatch(patch(listOf(1000, 1000, 1000, 1000, 1000, 4000, 4000, 0, 0)),
            3, 3, 16, 4, 1, 1)!!, 0f)
        assertNull(sampler.samplePatch(patch(listOf(1000, 1000, 1000, 1000, 3000, 3000, 3000, 3000, 0)),
            3, 3, 16, 4, 1, 1))
    }

    @Test fun missingAndTruncatedDepthCannotLookLikeAgreement() {
        assertNull(sampler.samplePatch(patch(List(9) { 0 }), 3, 3, 16, 4, 1, 1))
        assertNull(sampler.samplePatch(patch(List(9) { 65535 }), 3, 3, 16, 4, 1, 1))
        assertNull(sampler.samplePatch(ByteBuffer.allocate(1), 3, 3, 16, 4, 1, 1))
        assertNull(sampler.samplePatch(patch(List(9) { 1000 }), 3, 3, 16, 4, 0, 0))
    }
}
