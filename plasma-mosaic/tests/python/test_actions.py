import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("map_actions", Path(__file__).resolve().parents[2] / "contents" / "lib" / "mosaic" / "actions.py")
actions = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(actions)


class FolderActionsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_configuration_file_opens_its_parent_directory(self):
        location = self.root / 'settings; $(touch nope) <b>.conf'
        location.write_text('private contents')
        self.assertEqual(actions.directory_for(str(location)), str(self.root))

    def test_replaced_directory_symlink_is_rejected(self):
        target = self.root / 'target'
        target.mkdir()
        alias = self.root / 'alias'
        alias.symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError):
            actions.directory_for(str(alias))
        (target / 'settings').write_text('private')
        with self.assertRaises(ValueError):
            actions.directory_for(str(alias / 'settings'))

    def test_special_missing_and_traversal_locations_are_rejected(self):
        fifo = self.root / 'fifo'
        os.mkfifo(fifo)
        with self.assertRaises(ValueError):
            actions.directory_for(str(fifo))
        with self.assertRaises(FileNotFoundError):
            actions.directory_for(str(self.root / 'gone'))
        with self.assertRaises(ValueError):
            actions.directory_for(str(self.root) + '/../elsewhere')
        with self.assertRaises(ValueError):
            actions.directory_for('relative')


if __name__ == '__main__':
    unittest.main()
