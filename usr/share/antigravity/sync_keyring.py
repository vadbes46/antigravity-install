#!/usr/bin/env python3
import os
import json
import dbus
import time
from datetime import datetime, timezone, timedelta

def get_current_account():
    cockpit_dir = os.path.expanduser("~/.antigravity_cockpit")
    accounts_file = os.path.join(cockpit_dir, "accounts.json")
    if not os.path.exists(accounts_file):
        print(f"Error: {accounts_file} does not exist.")
        return None
        
    with open(accounts_file, "r") as f:
        data = json.load(f)
        
    current_id = data.get("current_account_id")
    if not current_id:
        print("Error: current_account_id not found in accounts.json")
        return None
        
    account_file = os.path.join(cockpit_dir, "accounts", f"{current_id}.json")
    if not os.path.exists(account_file):
        print(f"Error: Account detail file {account_file} does not exist.")
        return None
        
    with open(account_file, "r") as f:
        account_data = json.load(f)
        
    return account_data

def sync_keyring():
    account = get_current_account()
    if not account:
        return False
        
    token = account.get("token")
    if not token:
        print("Error: No token info in current account data.")
        return False
        
    access_token = token.get("access_token")
    refresh_token = token.get("refresh_token")
    expiry_timestamp = token.get("expiry_timestamp")
    token_type = token.get("token_type", "Bearer")
    
    if not access_token or not refresh_token or not expiry_timestamp:
        print("Error: Missing access_token, refresh_token, or expiry_timestamp.")
        return False
        
    # Convert expiry timestamp to ISO 8601 string with local timezone offset
    tz_offset = -time.timezone if time.daylight == 0 else -time.altzone
    tz = timezone(timedelta(seconds=tz_offset))
    dt = datetime.fromtimestamp(expiry_timestamp, tz)
    expiry_iso = dt.isoformat()
    
    # Secret payload
    secret_data = {
        "token": {
            "access_token": access_token,
            "token_type": token_type,
            "refresh_token": refresh_token,
            "expiry": expiry_iso
        },
        "auth_method": "consumer"
    }
    secret_value = json.dumps(secret_data).encode('utf-8')
    
    try:
        bus = dbus.SessionBus()
        service = bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets")
        service_iface = dbus.Interface(service, "org.freedesktop.Secret.Service")

        # Open session (plain text)
        session_param = dbus.String("", variant_level=1)
        output = service_iface.OpenSession("plain", session_param)
        session_path = output[1]

        # Properties of the item
        properties = dbus.Dictionary({
            dbus.String("org.freedesktop.Secret.Item.Label"): dbus.String("Password for 'antigravity' on 'gemini'"),
            dbus.String("org.freedesktop.Secret.Item.Attributes"): dbus.Dictionary({
                dbus.String("service"): dbus.String("gemini"),
                dbus.String("username"): dbus.String("antigravity"),
                dbus.String("xdg:schema"): dbus.String("org.freedesktop.Secret.Generic")
            }, signature="ss")
        }, signature="sv")

        # Secret struct: (session_path, parameters, value, content_type)
        secret_struct = dbus.Struct((
            dbus.ObjectPath(session_path),
            dbus.ByteArray(b""),
            dbus.ByteArray(secret_value),
            dbus.String("text/plain")
        ), signature="oayays")

        login_collection = bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets/collection/login")
        collection_iface = dbus.Interface(login_collection, "org.freedesktop.Secret.Collection")
        
        item_path, prompt_path = collection_iface.CreateItem(properties, secret_struct, True)
        print(f"Successfully synchronized token to keyring: {item_path} for email {account.get('email')}")
        return True
    except Exception as e:
        print(f"Error synchronizing keyring: {e}")
        return False

if __name__ == "__main__":
    sync_keyring()
