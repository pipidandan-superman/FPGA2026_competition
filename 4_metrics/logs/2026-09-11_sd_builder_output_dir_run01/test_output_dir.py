import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path('E:/competition_worktrees/FPGA2026_competition/pipidandan-superman/3_host/pynq/sd_boot_builder_v02')
sys.path.insert(0, str(SOURCE))
from builder import Builder, BuildError


class OutputTests(unittest.TestCase):
    def test_default_keeps_original_location(self):
        job = Builder('unused.xsa')
        source = job.run / 'output'
        self.assertIsNone(job.output_dir)
        self.assertEqual(job.publish_export(source), source)

    def test_custom_unicode_space_and_repeated_builds(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            parent = Path(temp) / '部署包 output'
            destinations = []
            for _ in range(2):
                job = Builder('unused.xsa', output_dir=str(parent), log=lambda _: None)
                job.run = Path(temp) / job.run.name
                source = job.run / 'output'
                source.mkdir(parents=True)
                (source / 'sd_boot_package.zip').write_bytes(b'zip fixture')
                (source / 'ees331_pynq_sd.img').write_bytes(b'image fixture' * 100)
                job.prepare_export()
                output = job.publish_export(source)
                destinations.append(output)
                self.assertEqual((output / 'ees331_pynq_sd.img').read_bytes(), b'image fixture' * 100)
                self.assertEqual(json.loads((job.run / 'export_validation.json').read_text(encoding='utf-8'))['result'], 'CUSTOM_OUTPUT_READBACK_PASS')
                with self.assertRaises(BuildError):
                    job.publish_export(source)
            self.assertNotEqual(*destinations)
            self.assertFalse(list(parent.glob('.pending-*')))

    def test_file_as_parent_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            target = Path(temp) / 'occupied'
            target.write_bytes(b'preserve')
            with self.assertRaises(FileExistsError):
                Builder('unused.xsa', output_dir=str(target)).prepare_export()
            self.assertEqual(target.read_bytes(), b'preserve')

    def test_readback_failure_not_published(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temp:
            job = Builder('unused.xsa', output_dir=str(Path(temp) / 'exports'), log=lambda _: None)
            job.run = Path(temp) / job.run.name
            source = job.run / 'output'
            source.mkdir(parents=True)
            (source / 'test.zip').write_bytes(b'payload')
            job.prepare_export()
            with patch('builder.hashlib.file_digest') as digest:
                digest.return_value.hexdigest.return_value = 'wrong'
                with self.assertRaises(BuildError):
                    job.publish_export(source)
            self.assertFalse((job.output_dir / job.run.name).exists())

    def test_frozen_project_rejected(self):
        with self.assertRaises(BuildError):
            Builder('unused.xsa', output_dir='E:/competition/2_fpga/new_output').prepare_export()


if __name__ == '__main__':
    unittest.main(verbosity=2)
