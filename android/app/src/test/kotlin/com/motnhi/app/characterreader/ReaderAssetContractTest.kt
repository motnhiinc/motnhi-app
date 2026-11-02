package com.motnhi.app.characterreader

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ReaderAssetContractTest {
    private fun gltf(file: String): JSONObject {
        val bytes = RuntimeEnvironment.getApplication().assets.open(file).use { it.readBytes() }
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(0x46546C67, header.getInt(0)) // glTF
        assertEquals(2, header.getInt(4))
        assertEquals(bytes.size, header.getInt(8))
        assertEquals(0x4E4F534A, header.getInt(16)) // JSON first chunk
        return JSONObject(String(bytes, 20, header.getInt(12), Charsets.UTF_8))
    }

    @Test fun everyBundledCharacterHasKnownNamesAndNoApprovedSpeakingClip() {
        val assets = (1..6).map { "cute_doll_v0$it.glb" } + "scan_any_page_character.glb"
        for (asset in assets) {
            val json = gltf(asset)
            val animations = json.getJSONArray("animations")
            val names = (0 until animations.length()).map {
                animations.getJSONObject(it).getString("name")
            }.toSet()
            assertTrue("$asset must have the audited named Idle", "Idle" in names)
            assertEquals("Idle", ReaderPresentationPolicy.animationName(true, names))
            assertEquals("Idle", ReaderPresentationPolicy.animationName(false, names))
            assertEquals(0f, ReaderPresentationPolicy.forwardOffsetDegrees(asset), 0f)
        }
    }

    @Test fun dollFrontMaterialsStayOnPositiveZAcrossEveryVariant() {
        for (variant in 1..6) {
            val json = gltf("cute_doll_v0$variant.glb")
            val materials = json.getJSONArray("materials")
            val primitives = json.getJSONArray("meshes").getJSONObject(0).getJSONArray("primitives")
            val seen = mutableSetOf<String>()
            for (index in 0 until primitives.length()) {
                val primitive = primitives.getJSONObject(index)
                val name = materials.getJSONObject(primitive.getInt("material")).getString("name")
                if (name.startsWith("Eye_") || name.startsWith("Mouth_")) {
                    seen += name.substringBefore('_')
                    val accessor = json.getJSONArray("accessors").getJSONObject(
                        primitive.getJSONObject("attributes").getInt("POSITION"))
                    assertTrue("$name must face +Z", accessor.getJSONArray("min").getDouble(2) > 0)
                }
            }
            assertEquals(setOf("Eye", "Mouth"), seen)
        }
    }
}
