import sys
import time
from pathlib import Path
RUN=Path(__file__).resolve().parent
sys.path.insert(0,'E:/competition/4_metrics/logs/2026-09-11_pynq_camera_run01/deps')
import serial
p=serial.Serial(port=None,baudrate=115200,timeout=.2,rtscts=False,dsrdtr=False)
p.dtr=False
p.rts=False
p.port='COM6'
with (RUN/(sys.argv[1]+'.raw')).open('xb') as log:
    p.open()
    try:
        if len(sys.argv)>2:
            p.write(sys.argv[2].encode()+b'\r')
        end=time.monotonic()+10
        while time.monotonic()<end:
            data=p.read(p.in_waiting or 1)
            if data:
                log.write(data)
                log.flush()
                print(data.decode(errors='replace'),end='',flush=True)
    finally:
        p.close()
