import argparse
import os
import sys
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
a = p.parse_args()
logpath = RUN / (a.label + '.log')
if logpath.exists():
    raise RuntimeError('Evidence label already exists')
client = paramiko.SSHClient()
client.load_host_keys(str(PRIOR / 'known_hosts'))
client.set_missing_host_key_policy(paramiko.RejectPolicy())
status = 1
with logpath.open('x', encoding='utf-8') as log:
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
                    sftp.get(*a.get)
            output = 'SFTP_COMPLETE ' + repr(a.put or a.get)
            status = 0
        else:
            log.write('COMMAND: ' + a.command + '\n')
            log.flush()
            inp, out, err = client.exec_command(a.command, timeout=120)
            if a.command.startswith('sudo -S '):
                inp.write(os.environ.get('PYNQ_PASSWORD', 'xilinx') + '\n')
                inp.flush()
            output = out.read().decode(errors='replace') + err.read().decode(errors='replace')
            status = out.channel.recv_exit_status()
        log.write(output + '\nEXIT: ' + str(status) + '\n')
        print(output)
    except Exception as exc:
        log.write(type(exc).__name__ + ': ' + str(exc) + '\n')
        print(type(exc).__name__ + ': ' + str(exc))
    finally:
        client.close()
sys.exit(status)
