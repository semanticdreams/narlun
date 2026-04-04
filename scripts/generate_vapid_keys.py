import base64

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


def _urlsafe_b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def main():
    private_key = ec.generate_private_key(ec.SECP256R1())
    private_numbers = private_key.private_numbers()
    public_numbers = private_numbers.public_numbers

    public_key_bytes = b'\x04' + public_numbers.x.to_bytes(32, 'big') + public_numbers.y.to_bytes(32, 'big')
    private_key_bytes = private_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )

    print(f'PUSH_VAPID_PUBLIC_KEY={_urlsafe_b64(public_key_bytes)}')
    print(f'PUSH_VAPID_PRIVATE_KEY={_urlsafe_b64(private_key_bytes)}')
    print('PUSH_VAPID_SUBJECT=mailto:admin@example.com')


if __name__ == '__main__':
    main()
