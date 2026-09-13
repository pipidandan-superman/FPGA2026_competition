"""Inject known commands through PC UDP->PS AXI and check captured PL TX."""
import argparse
import json
from pathlib import Path
import subprocess
import queue
import threading
import time
from action_link import ActionClient
from action_protocol import uart_frame, command, decode_reply, DUPLICATE, UartFrames


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--run-dir",type=Path,required=True)
    parser.add_argument("--host",default="192.168.240.10")
    parser.add_argument("--port",default="COM4")
    parser.add_argument("--rounds",type=int,default=1000)
    parser.add_argument("--visual",action="store_true")
    args=parser.parse_args()
    if not args.run_dir.resolve().is_relative_to(Path("E:/competition/4_metrics/logs")):
        parser.error("Evidence must be under 4_metrics/logs")
    args.run_dir.mkdir(parents=True,exist_ok=False)
    events=(args.run_dir/"events.jsonl").open("x",buffering=1)
    output=(args.run_dir/"serial_console.txt").open("x",buffering=1)
    capture=args.run_dir/"com4.bin"
    # Include UDP confirmation/replay and Windows timer granularity, not only
    # the 7.3 ms UART wire time. Keep capturing well past the final command.
    seconds=25 if args.visual else max(15,args.rounds*.15+30)
    proc=subprocess.Popen(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",
        str(Path(__file__).with_name("serial_capture.ps1")),"-Port",args.port,
        "-Output",str(capture),"-Seconds",str(seconds)],stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,text=True)
    readiness=queue.Queue(maxsize=1)
    def drain():
        for line in proc.stdout:
            output.write(line); output.flush()
            if "SERIAL_CAPTURE_READY" in line:
                readiness.put(True)
    reader=threading.Thread(target=drain,daemon=True)
    reader.start()
    expected=[]
    result=dict(state="INCOMPLETE")
    client=None
    try:
        client=ActionClient(args.host)
        # The helper emits readiness before the first command is submitted.
        try:
            readiness.get(timeout=5)
        except queue.Empty:
            raise RuntimeError("COM4 capture not ready; see serial_console.txt")
        state=client.synchronize()
        events.write(json.dumps(dict(event="SYNCHRONIZED",**state))+"\n")
        rounds=8 if args.visual else args.rounds
        for index in range(rounds):
            action=index%8
            out=client.execute(action)
            expected.append(uart_frame(out["seq"],action))
            events.write(json.dumps(dict(event="COMMAND_PASS",index=index,**out))+"\n")
            # Duplicate replay is verified against the real PS service; UART
            # bytes below must still contain exactly one frame per command.
            if not args.visual:
                client.sock.send(command(out["seq"],action))
                replay=decode_reply(client.sock.recv(2048))
                if replay["status"]!=DUPLICATE or replay["done_seq"]!=out["seq"]:
                    raise RuntimeError("Duplicate handling mismatch")
                time.sleep(.04)  # Bound test rate; keep video co-running.
            else:
                print("VISUAL action="+str(action),flush=True)
                time.sleep(2)
        # Return to CLEAR using AXI, also part of the serial evidence.
        out=client.execute(0)
        expected.append(uart_frame(out["seq"],0))
        events.write(json.dumps(dict(event="FINAL_CLEAR",**out))+"\n")
        proc.wait(timeout=seconds+5)
        reader.join(2)
        if proc.returncode:
            raise RuntimeError("Serial helper failed")
        raw=capture.read_bytes()
        decoded=UartFrames()
        frames=decoded.feed(raw)
        if (frames!=expected or decoded.errors or decoded.discarded or decoded.buffer or
                raw!=b"".join(expected)):
            raise RuntimeError(f"UART mismatch expected={len(expected)} actual={len(frames)}")
        result=dict(state="PASS",marker="ACTION_V1_COM4_BOARD_PASS",commands=rounds,
                    total_with_clear=len(expected),bytes=len(raw),final=out,
                    physical_led="USER_CONFIRMATION_REQUIRED")
    except BaseException as exc:
        result=dict(state="FAIL",error=repr(exc),confirmed_commands=len(expected))
    finally:
        if client is not None:
            client.close()
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=5)
        reader.join(2)
        events.close();output.close()
        (args.run_dir/"expected.bin").write_bytes(b"".join(expected))
        (args.run_dir/"result.json").write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
    return 0 if result["state"]=="PASS" else 1


if __name__=="__main__":
    raise SystemExit(main())
