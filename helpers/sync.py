#!/usr/bin/env python3
"""
Synchronize Antigravity conversation summary metadata between:
1) ~/.gemini/antigravity/agyhub_summaries_proto.pb (standalone/hub format)
2) ~/.config/Antigravity/User/globalStorage/state.vscdb (IDE format)

What this script does:
- Reads summary entries from both sources.
- Normalizes entries into a unified representation by trajectory UUID.
- Writes merged summaries back to:
  - agyhub_summaries_proto.pb (standalone protobuf wire format)
  - state.vscdb keys
    - antigravityUnifiedStateSync.trajectorySummaries
    - unifiedStateSync.trajectorySummaries
    in base64 IDE format.
- Creates .bak backups for both files before writing.
- Force-kills active antigravity/antigravity-ide processes so refreshed metadata
  is loaded on next launch.
"""

import os
import sqlite3
import base64
import shutil
import signal

def read_varint(data, pos):
    val = 0
    shift = 0
    while True:
        b = data[pos]
        pos += 1
        val |= (b & 0x7f) << shift
        if not (b & 0x80):
            break
        shift += 7
    return val, pos

def write_varint(val):
    res = bytearray()
    while True:
        b = val & 0x7f
        val >>= 7
        if val > 0:
            res.append(b | 0x80)
        else:
            res.append(b)
            break
    return bytes(res)

def normalize_entry(entry_bytes):
    if not entry_bytes or len(entry_bytes) == 0:
        return None
    if entry_bytes[0] != 10: # field 1, wire type 2
        return None
    
    try:
        uuid_len, pos = read_varint(entry_bytes, 1)
        uuid = entry_bytes[pos:pos+uuid_len].decode('ascii', errors='ignore')
        pos += uuid_len
    except Exception:
        return None
        
    # Parse field 2 (tag 18 = 0x12)
    details_bytes = None
    if pos < len(entry_bytes) and entry_bytes[pos] == 18:
        pos += 1
        try:
            f2_len, pos = read_varint(entry_bytes, pos)
            f2_data = entry_bytes[pos:pos+f2_len]
        except Exception:
            return None
            
        # Check if f2_data is in IDE format (starts with tag 10 containing base64)
        if len(f2_data) > 0 and f2_data[0] == 10:
            try:
                str_len, spos = read_varint(f2_data, 1)
                str_val = f2_data[spos:spos+str_len]
                # Try base64 decoding
                decoded = base64.b64decode(str_val)
                # Valid protobuf tags standard in TrajectorySummary (10 for title, 18 for workspace, etc.)
                if len(decoded) > 0 and decoded[0] in [10, 18, 24, 26]:
                    details_bytes = decoded
                else:
                    details_bytes = f2_data
            except Exception:
                details_bytes = f2_data
        else:
            details_bytes = f2_data
    else:
        # Fallback if no field 2 tag found (should not happen for valid summaries)
        details_bytes = entry_bytes[pos:]
        
    if not details_bytes:
        return None
        
    # 1. Standalone format: raw binary details_bytes directly inside field 2
    standalone_entry = b'\x0a' + write_varint(36) + uuid.encode('ascii') + b'\x12' + write_varint(len(details_bytes)) + details_bytes
    
    # 2. IDE format: base64-encoded string inside tag 10 inside field 2
    b64_str = base64.b64encode(details_bytes).decode('ascii')
    inner_container = b'\x0a' + write_varint(len(b64_str)) + b64_str.encode('ascii')
    ide_entry = b'\x0a' + write_varint(36) + uuid.encode('ascii') + b'\x12' + write_varint(len(inner_container)) + inner_container
    
    return uuid, standalone_entry, ide_entry

def parse_summaries(path):
    if not os.path.exists(path):
        return []
    with open(path, 'rb') as f:
        data = f.read()
    
    pos = 0
    entries = []
    while pos < len(data):
        if data[pos] != 10:
            break
        pos += 1
        length, pos = read_varint(data, pos)
        entry_data = data[pos:pos+length]
        pos += length
        entries.append(entry_data)
    return entries

def parse_base64_summaries(b64_str):
    if not b64_str:
        return []
    try:
        data = base64.b64decode(b64_str)
    except Exception:
        return []
    pos = 0
    entries = []
    while pos < len(data):
        if data[pos] != 10:
            break
        pos += 1
        length, pos = read_varint(data, pos)
        entry_data = data[pos:pos+length]
        pos += length
        entries.append(entry_data)
    return entries

def get_value(db, key):
    conn = sqlite3.connect(db)
    res = conn.execute('SELECT value FROM ItemTable WHERE key=?', (key,)).fetchone()
    conn.close()
    return res[0] if res else None

def update_value(db, key, val):
    conn = sqlite3.connect(db)
    conn.execute('INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)', (key, val))
    conn.commit()
    conn.close()

def main():
    active_gemini = os.path.expanduser('~/.gemini/antigravity')
    active_pb = os.path.join(active_gemini, 'agyhub_summaries_proto.pb')
    active_db = os.path.expanduser('~/.config/Antigravity/User/globalStorage/state.vscdb')
    
    print("=== Syncing Metadata ===")
    
    # 1. Parse agyhub_summaries_proto.pb
    pb_raw_entries = parse_summaries(active_pb)
    print(f"Read {len(pb_raw_entries)} raw summaries from agyhub_summaries_proto.pb")
    
    # 2. Parse state.vscdb summaries
    db_raw_entries = []
    if os.path.exists(active_db):
        for key in ['antigravityUnifiedStateSync.trajectorySummaries', 'unifiedStateSync.trajectorySummaries']:
            val = get_value(active_db, key)
            parsed = parse_base64_summaries(val)
            print(f"Read {len(parsed)} raw summaries from state.vscdb [{key}]")
            db_raw_entries.extend(parsed)
            
    # 3. Unify and normalize all entries to both formats
    standalone_entries = {}
    ide_entries = {}
    
    for raw in pb_raw_entries + db_raw_entries:
        res = normalize_entry(raw)
        if res:
            uuid, standalone, ide = res
            standalone_entries[uuid] = standalone
            ide_entries[uuid] = ide
            
    print(f"Total unified unique conversations: {len(standalone_entries)}")
    
    # 4. Serialize back to agyhub_summaries_proto.pb (in Standalone Format)
    merged_pb_bytes = bytearray()
    for uuid, entry_bytes in standalone_entries.items():
        merged_pb_bytes.extend(b'\x0a')
        merged_pb_bytes.extend(write_varint(len(entry_bytes)))
        merged_pb_bytes.extend(entry_bytes)
        
    if os.path.exists(active_pb):
        shutil.copy2(active_pb, active_pb + '.bak')
    with open(active_pb, 'wb') as f:
        f.write(merged_pb_bytes)
    print("Wrote updated agyhub_summaries_proto.pb in STANDALONE format")
    
    # 5. Serialize back to state.vscdb (in IDE Format)
    if os.path.exists(active_db):
        shutil.copy2(active_db, active_db + '.bak')
        
        merged_db_bytes = bytearray()
        for uuid, entry_bytes in ide_entries.items():
            merged_db_bytes.extend(b'\x0a')
            merged_db_bytes.extend(write_varint(len(entry_bytes)))
            merged_db_bytes.extend(entry_bytes)
            
        merged_b64 = base64.b64encode(merged_db_bytes).decode('ascii')
        for key in ['antigravityUnifiedStateSync.trajectorySummaries', 'unifiedStateSync.trajectorySummaries']:
            update_value(active_db, key, merged_b64)
        print("Wrote updated state.vscdb in IDE format")
        
    # 6. Force-kill IDE and standalone processes to apply changes
    print("\n=== Force-killing Active IDE & Standalone Processes ===")
    mypid = os.getpid()
    killed_any = False
    for pid in os.listdir('/proc'):
        if pid.isdigit():
            try:
                with open(f'/proc/{pid}/cmdline', 'r') as f:
                    cmd = f.read()
                if ('antigravity-ide' in cmd or 'antigravity' in cmd) and int(pid) != mypid:
                    print(f"Killing PID {pid}: {cmd[:50]}")
                    os.kill(int(pid), signal.SIGKILL)
                    killed_any = True
            except Exception:
                pass
                
    print("\nSynchronization completed successfully!")
    if killed_any:
        print("Please reopen your IDE and/or standalone app now to view the unified list!")

if __name__ == '__main__':
    main()
