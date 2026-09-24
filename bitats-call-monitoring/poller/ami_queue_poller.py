#!/usr/bin/env python3
import os, socket, time, mysql.connector, re
from datetime import datetime

# Параметры AMI берутся из переменных окружения (см. ami-queue-poller.env.example)
AMI_HOST = os.environ.get("AMI_HOST", "127.0.0.1")
AMI_PORT = int(os.environ.get("AMI_PORT", "5038"))
AMI_USER = os.environ.get("AMI_USER", "bitpbx")
AMI_PASS = os.environ["AMI_PASS"]  # обязательный параметр, в коде не хранится

DB = {"unix_socket": "/run/mysqld/mysqld.sock", "user": "root", "database": "pbxanalytics"}

# Соответствие номера очереди в AMI -> (добавочный очереди, название).
# Заполняется под конкретную АТС. Значения ниже приведены как пример.
QUEUE_MAP = {
    "1": ("501", "Queue 501"),
    "2": ("502", "Queue 502"),
    "3": ("503", "Queue 503"),
    "4": ("504", "Queue 504"),
}

def ami_connect():
    s = socket.socket()
    s.settimeout(10)
    s.connect((AMI_HOST, AMI_PORT))
    s.recv(1024)
    s.sendall(f"Action: Login\r\nUsername: {AMI_USER}\r\nSecret: {AMI_PASS}\r\n\r\n".encode())
    s.recv(1024)
    return s

def ami_queue_status(s):
    s.sendall(b"Action: QueueStatus\r\nActionID: qs1\r\n\r\n")
    buf = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
        if b"QueueStatusComplete" in buf:
            break
    return buf.decode(errors="replace")

def extract_ext(state_interface):
    # hint:q20908@users-notify -> 20908
    m = re.search(r'hint:q(\d+)@', state_interface)
    if m:
        return m.group(1)
    return ""

def parse_events(raw):
    queues, entries, members = {}, {}, []
    current = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            if current:
                etype = current.get("Event", "")
                ami_q = current.get("Queue", "")
                q_num, q_name = QUEUE_MAP.get(ami_q, (ami_q, ami_q))
                if etype == "QueueParams":
                    queues[q_num] = {"name": q_name, "calls_waiting": int(current.get("Calls", 0)),
                                     "max_wait_sec": 0, "members_avail": 0, "members_busy": 0, "members_paused": 0}
                elif etype == "QueueMember":
                    if q_num not in queues:
                        queues[q_num] = {"name": q_name, "calls_waiting": 0, "max_wait_sec": 0,
                                          "members_avail": 0, "members_busy": 0, "members_paused": 0}
                    paused = current.get("Paused", "0") == "1"
                    try:
                        status = int(current.get("Status", "0"))
                    except ValueError:
                        status = 0
                    if paused:
                        queues[q_num]["members_paused"] += 1
                    elif status == 1:
                        queues[q_num]["members_avail"] += 1
                    elif status in (2, 6):
                        queues[q_num]["members_busy"] += 1
                    ext = extract_ext(current.get("StateInterface", ""))
                    name = current.get("Name", ext or "unknown")
                    members.append((q_num, ext, name, 1 if paused else 0, status))
                elif etype == "QueueEntry":
                    wait = int(current.get("Wait", 0))
                    pos = int(current.get("Position", 0))
                    cid = current.get("CallerIDNum", "")
                    entries.setdefault(q_num, []).append({"position": pos, "callerid": cid, "wait_sec": wait})
                    if q_num in queues:
                        queues[q_num]["max_wait_sec"] = max(queues[q_num]["max_wait_sec"], wait)
            current = {}
        elif ":" in line:
            k, _, v = line.partition(":")
            current[k.strip()] = v.strip()
    return queues, entries, members

def write_db(queues, entries, members):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cn = mysql.connector.connect(**DB)
    cur = cn.cursor()
    for q_num, d in queues.items():
        cur.execute("""INSERT INTO rt_queue_status
              (ts, queue, calls_waiting, max_wait_sec, members_avail, members_busy, members_paused)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON DUPLICATE KEY UPDATE calls_waiting=VALUES(calls_waiting), max_wait_sec=VALUES(max_wait_sec),
              members_avail=VALUES(members_avail), members_busy=VALUES(members_busy), members_paused=VALUES(members_paused)""",
            (ts, q_num, d["calls_waiting"], d["max_wait_sec"], d["members_avail"], d["members_busy"], d["members_paused"]))
    for q_num, elist in entries.items():
        for e in elist:
            cur.execute("""INSERT INTO rt_queue_entries (ts, queue, position, callerid, wait_sec)
                VALUES (%s,%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE callerid=VALUES(callerid), wait_sec=VALUES(wait_sec)""",
                (ts, q_num, e["position"], e["callerid"], e["wait_sec"]))
    for (q_num, ext, name, paused, ami_status) in members:
        cur.execute("""INSERT INTO rt_member_status (ts, queue, ext, name, paused, ami_status)
            VALUES (%s,%s,%s,%s,%s,%s)
            ON DUPLICATE KEY UPDATE name=VALUES(name), paused=VALUES(paused), ami_status=VALUES(ami_status)""",
            (ts, q_num, ext, name, paused, ami_status))
    cn.commit(); cur.close(); cn.close()

def run():
    while True:
        try:
            s = ami_connect()
            raw = ami_queue_status(s)
            s.close()
            queues, entries, members = parse_events(raw)
            write_db(queues, entries, members)
            waiting = {q: d["calls_waiting"] for q, d in queues.items() if d["calls_waiting"] > 0}
            print(f"{datetime.now():%H:%M:%S} | queues={len(queues)} members={len(members)} waiting={waiting}")
        except Exception as e:
            print(f"ERROR: {e}")
        time.sleep(30)

if __name__ == "__main__":
    run()
