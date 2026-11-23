import importlib.machinery
import importlib.util
import unittest

from helpers import ROOT

PATH = ROOT / "files/core-system/usr/libexec/gill-osaab/gosaab-android-notify"
loader = importlib.machinery.SourceFileLoader("android_notify", str(PATH))
spec = importlib.util.spec_from_loader("android_notify", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

DUMP = """
Current Notification Manager state:
  Notification List:
    NotificationRecord(0x0a1b2c3d: pkg=com.android.vending user=UserHandle{0} id=12 tag=null importance=2 key=0|com.android.vending|12|null|10074: Notification(channel=download))
      uid=10074 userId=0
      extras={
        android.title=String (Downloading Instagram)
        android.text=String (12 MB of 50 MB)
        android.progress=Integer (24)
        android.progressMax=Integer (100)
        android.progressIndeterminate=Boolean (false)
      }
    NotificationRecord(0x0e0f0a0b: pkg=com.whatsapp user=UserHandle{0} id=1 tag=null importance=4 key=0|com.whatsapp|1|null|10080: Notification(channel=msg))
      extras={
        android.title=String (Mum)
        android.text=String (Call me when you're free)
      }
  Snoozed notifications:
    NotificationRecord(0x0f: pkg=com.snoozed user=UserHandle{0} id=3 tag=null importance=2 key=0|com.snoozed|3|null|1: Notification())
      extras={
        android.title=String (Hidden)
      }
"""


class AndroidNotify(unittest.TestCase):
    def test_parses_posted_notifications_with_progress(self):
        got = mod.parse(DUMP)
        self.assertEqual(len(got), 2)
        dl = got["0|com.android.vending|12|null|10074"]
        self.assertEqual((dl["app"], dl["title"], dl["percent"]), ("Play Store", "Downloading Instagram", 24))
        msg = got["0|com.whatsapp|1|null|10080"]
        self.assertEqual((msg["app"], msg["text"], msg["percent"]), ("WhatsApp", "Call me when you're free", None))

    def test_empty_dump(self):
        self.assertEqual(mod.parse(""), {})


if __name__ == "__main__":
    unittest.main()
