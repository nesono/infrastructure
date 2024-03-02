import socket
import sys
import os
import base64

# Ensure username and password are provided as command-line arguments
if len(sys.argv) != 3:
    print("Usage: script.py <username> <password>")
    sys.exit(1)

username = sys.argv[1]
password = sys.argv[2]

# Define the socket path
socket_path = '/svc/volumes/mail_spool/private/auth'


def sasl_plain(username, password, authzid=''):
    return  base64.b64encode(f'{authzid}\0{username}\0{password}').encode()


try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client_socket:
        print(f"conecting to {socket_path}")
        client_socket.connect(socket_path)

        print("sending version")
        client_socket.send(b'VERSION\t1\t2\r\n')

        client_pid = os.getpid()
        print(f"sending client process ID: {client_pid}")
        client_socket.send(b'CPID\t' + str(client_pid).encode())

        print("sending auth login")
        client_socket.send(b'AUTH\t1\tPLAIN service=imap resp='+sasl_plain(username, password))

        data = client_socket.recv(1024)
        print("Server response:", data.decode())
except socket.error as e:
    print(f"Socket error: {e}")
    sys.exit(1)
