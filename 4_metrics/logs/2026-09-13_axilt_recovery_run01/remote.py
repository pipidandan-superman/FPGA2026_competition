import argparse
import os
import sys
import time
from pathlib import Path
RUN = Path(__file__).resolve().parent
PRIOR = Path('E:/competition/4_metrics/logs/2026-09-11_pynq_camera_run01')
sys.path.insert(0, str(PRIOR / 'deps'))
import paramiko
p = argparse.ArgumentParser()
p.add_argument('command', nargs='?', default='id')
p.add_argument('--label', required=True)
p.add_argument('--put', nargs=2)
p.add_argument('--get', nargs=2)
p.add_argument('--timeout', type=float, default=90)
a = p.parse_args()
client = paramiko.SSHClient()
client.load_host_keys(str(PRIOR / 'known_hosts'))
client.set_missing_host_key_policy(paramiko.RejectPolicy())
status = 1
with (RUN / (a.label + '.log')).open('x', encoding='utf-8') as log:
    def emit(s):
        log.write(s)
        log.flush()
        print(s, end='', flush=True)
    try:
        client.connect('192.168.240.10', username='xilinx',
                       password=os.environ.get('PYNQ_PASSWORD', 'xilinx'),
                       look_for_keys=False, allow_agent=False, timeout=8,
                       banner_timeout=8, auth_timeout=8)
        if a.put or a.get:
            with client.open_sftp() as sftp:
                if a.put:
                    sftp.put(*a.put)
                else:
                    if Path(a.get[1]).exists():
                        raise RuntimeError('Destination exists')
                    sftp.get(*a.get)
            emit('SFTP_COMPLETE ' + repr(a.put or a.get) + '\n')
            status = 0
        else:
            emit('COMMAND: ' + a.command + '\n')
            inp, out, err = client.exec_command(a.command, timeout=10)
            if a.command.startswith('sudo -S '):
                inp.write(os.environ.get('PYNQ_PASSWORD', 'xilinx') + '\n')
                inp.flush()
            ch = out.channel
            deadline = time.monotonic() + a.timeout
            while True:
                while ch.recv_ready():
                    emit(ch.recv(65536).decode(errors='replace'))
                while ch.recv_stderr_ready():
                    emit(ch.recv_stderr(65536).decode(errors='replace'))
                if ch.exit_status_ready() and not ch.recv_ready() and not ch.recv_stderr_ready():
                    status = ch.recv_exit_status()
                    break
                if time.monotonic() > deadline:
                    raise TimeoutError('Remote deadline; board state may be unknown')
                time.sleep(.05)
        emit('\nEXIT: ' + str(status) + '\n')
    except Exception as exc:
        emit(type(exc).__name__ + ': ' + str(exc) + '\n')
    finally:
        client.close()
sys.exit(status)
