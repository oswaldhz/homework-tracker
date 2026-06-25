from cryptography.fernet import Fernet
import os
from config import ENCRYPTION_KEY_PATH

def get_or_create_key():
    if ENCRYPTION_KEY_PATH.exists():
        key = ENCRYPTION_KEY_PATH.read_bytes()
    else:
        key = Fernet.generate_key()
        ENCRYPTION_KEY_PATH.write_bytes(key)
    return key

def encrypt_value(value: str) -> str:
    f = Fernet(get_or_create_key())
    return f.encrypt(value.encode()).decode()

def decrypt_value(encrypted: str) -> str:
    f = Fernet(get_or_create_key())
    return f.decrypt(encrypted.encode()).decode()
