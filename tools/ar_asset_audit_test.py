"""Run: python -m unittest discover -s tools -p 'ar*_test.py' -v"""
import json
import struct
import unittest

from pxr import Gf
import ar_asset_audit as audit


class DecoderTests(unittest.TestCase):
    def test_interleaved_with_offsets(self):
        blob = b"HEAD" + struct.pack('<ffff', 99, 1, 99, 2)
        doc = {"bufferViews": [{"byteOffset": 4, "byteLength": 16, "byteStride": 8}],
               "accessors": [{"bufferView": 0, "byteOffset": 4, "componentType": 5126, "type": "SCALAR", "count": 2}]}
        self.assertEqual(audit.accessor(doc, blob, 0), [(1,), (2,)])

    def test_sparse_and_normalized(self):
        doc = {"bufferViews": [{"byteLength": 1}, {"byteOffset": 1, "byteLength": 2}],
               "accessors": [{"type": "VEC2", "componentType": 5120, "count": 2, "normalized": True,
                              "sparse": {"count": 1, "indices": {"bufferView": 0, "componentType": 5121},
                                         "values": {"bufferView": 1}}}]}
        self.assertEqual(audit.accessor(doc, bytes([1, 128, 127]), 0), [(0, 0), (-1, 1)])

    def test_accessor_bounds(self):
        doc = {"bufferViews": [{"byteLength": 2}], "accessors": [
            {"bufferView": 0, "type": "SCALAR", "componentType": 5126, "count": 1}]}
        with self.assertRaises(ValueError):
            audit.accessor(doc, b"1234", 0)

    def test_trs_order(self):
        m = audit.node_matrix({"translation": [1, 2, 3], "scale": [2, 3, 4]})
        self.assertEqual(tuple(m.Transform(Gf.Vec3d(1, 1, 1))), (3, 5, 7))

    def test_column_major_translation(self):
        m = audit.node_matrix({"matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1]})
        self.assertEqual(tuple(m.Transform(Gf.Vec3d(0, 0, 0))), (1, 2, 3))

    def test_prefixed_usd_root_joints(self):
        self.assertEqual(audit.joint_root_indices(['n52/n42', 'n52/n42/n37', 'n52/n44']), [0, 2])


class AssetContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = audit.audit()

    def test_all_pairs_and_no_uninspected_assets(self):
        assets = self.report['assets']
        self.assertEqual(len(assets), 14)
        self.assertEqual({a['file'].split('/')[-1].split('.')[0] for a in assets if a['format'] == 'glb'},
                         {a['file'].split('/')[-1].split('.')[0] for a in assets if a['format'] == 'usdz'})

    def test_glb_idle_contract_not_index(self):
        for asset in self.report['assets']:
            if asset['format'] == 'glb':
                names = [a['name'] for a in asset['metadata']['animations']]
                self.assertIn('Idle', names)
                self.assertEqual(len(names), len(set(names)))
                self.assertFalse(any(p['morph_target_count'] for p in asset['metadata']['primitives']))

    def test_usdz_single_clip_not_named_mapping_parity(self):
        for asset in self.report['assets']:
            if asset['format'] == 'usdz':
                animations = asset['metadata']['animations']
                self.assertEqual(len(animations), 1)
                self.assertTrue(animations[0]['path'].endswith('/SkelAnim'))
                self.assertTrue(animations[0]['root_channels_local_space'])
                self.assertFalse(animations[0]['blend_shapes'])

    def test_root_translation_matches_idle_between_formats(self):
        assets = self.report['assets']
        for glb in [a for a in assets if a['format'] == 'glb']:
            name = glb['file'].split('/')[-1].replace('.glb', '.usdz')
            usd = next(a for a in assets if a['file'].endswith('/' + name))
            idle = next(a for a in glb['metadata']['animations'] if a['name'] == 'Idle')
            channels = usd['metadata']['animations'][0]['root_channels_local_space']
            actual = channels[0]['key_values']['range']
            expected = idle['root_and_ancestor_channels_local_space'][0]['key_values']['range']
            for key in ['min', 'max']:
                for x, y in zip(actual[key], expected[key]):
                    self.assertAlmostEqual(x, y, places=6)

    def test_default_geometry_parity_not_runtime_pose(self):
        assets = self.report['assets']
        for glb in [a for a in assets if a['format'] == 'glb']:
            name = glb['file'].split('/')[-1].replace('.glb', '.usdz')
            usd = next(a for a in assets if a['file'].endswith('/' + name))
            gm, um = glb['metadata'], usd['metadata']
            self.assertEqual(gm['triangles'], sum(m['triangulated_face_count'] for m in um['meshes']))
            self.assertEqual(len(gm['primitives']), len(um['meshes']))
            for gp, up in zip(gm['primitives'], um['meshes']):
                self.assertEqual(gp['unskinned_world_bounds'], up['unskinned_world_bounds'])

    def test_checked_in_report_reproducible(self):
        expected = json.loads((audit.ROOT / 'docs/superpowers/audits/2026-10-22-ar-assets.json').read_text())
        self.assertEqual(self.report, expected)


if __name__ == '__main__':
    unittest.main()
