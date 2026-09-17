#!/bin/bash
# M13 run02 watcher: poll board log every 20s; exit 0=verdict seen, 1=driver error,
# 2=board unreachable 3x (freeze), 3=30min cap
export SSH_ASKPASS=/e/competition/2_fpga/3_yolo_zynq/pynq/pc_askpass.sh SSH_ASKPASS_REQUIRE=force DISPLAY=:0 EES331_SSH_PW=xilinx
fail=0
for i in $(seq 1 90); do
  out=$(ssh -o ConnectTimeout=8 xilinx@192.168.240.10 "tail -n 6 /home/xilinx/m13/board_run02.log 2>/dev/null; echo ---POLL---; tail -n 2 /home/xilinx/m13/status_poll02.log 2>/dev/null" 2>/dev/null)
  if [ -z "$out" ]; then
    fail=$((fail+1))
    echo "[watch] ssh FAIL #$fail at $(date +%H:%M:%S)"
    if [ $fail -ge 3 ]; then echo "[watch] BOARD_UNREACHABLE_3X freeze suspected"; exit 2; fi
  else
    fail=0
    echo "[watch $(date +%H:%M:%S)]"
    echo "$out"
    if echo "$out" | grep -q 'PL_M11_PASS'; then echo "[watch] VERDICT_PASS_SEEN"; exit 0; fi
    if echo "$out" | grep -qE 'PL_M11_FAIL|nerr=[1-9]|Traceback|SError'; then echo "[watch] DRIVER_FAIL_SEEN"; exit 1; fi
  fi
  sleep 20
done
echo "[watch] WATCH_30MIN_CAP"; exit 3
