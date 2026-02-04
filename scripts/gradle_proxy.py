#!/usr/bin/env python3
"""Local forwarding proxy for Gradle/Java in cloud environments.

Java's HttpURLConnection cannot authenticate with the container's HTTP proxy
during HTTPS CONNECT tunneling. This script runs a local proxy on port 18080
that transparently injects the Proxy-Authorization header.

Started by setup_env.sh when HTTP_PROXY is set.
"""
import socket
import threading
import base64
import os
from urllib.parse import urlparse

proxy_url = os.environ['HTTP_PROXY']
p = urlparse(proxy_url)
UPSTREAM_HOST = p.hostname
UPSTREAM_PORT = p.port
AUTH = base64.b64encode(f'{p.username}:{p.password}'.encode()).decode()

LOCAL_PORT = 18080


def handle_client(client_sock):
    try:
        request = b''
        while b'\r\n\r\n' not in request:
            chunk = client_sock.recv(4096)
            if not chunk:
                client_sock.close()
                return
            request += chunk

        first_line = request.split(b'\r\n')[0].decode()
        method = first_line.split()[0]

        # Connect to upstream proxy
        upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        upstream.connect((UPSTREAM_HOST, UPSTREAM_PORT))

        if method == 'CONNECT':
            target = first_line.split()[1]
            connect_req = (
                f'CONNECT {target} HTTP/1.1\r\n'
                f'Host: {target}\r\n'
                f'Proxy-Authorization: Basic {AUTH}\r\n'
                f'\r\n'
            ).encode()
            upstream.send(connect_req)

            resp = b''
            while b'\r\n\r\n' not in resp:
                chunk = upstream.recv(4096)
                if not chunk:
                    break
                resp += chunk

            client_sock.send(resp)

            if b'200' in resp.split(b'\r\n')[0]:
                relay(client_sock, upstream)
            else:
                client_sock.close()
                upstream.close()
        else:
            header_end = request.index(b'\r\n\r\n')
            headers = request[:header_end]
            body = request[header_end:]
            auth_header = f'Proxy-Authorization: Basic {AUTH}\r\n'.encode()
            first_line_end = headers.index(b'\r\n') + 2
            modified = headers[:first_line_end] + auth_header + headers[first_line_end:] + body
            upstream.send(modified)
            relay_one_way(upstream, client_sock)

    except Exception:
        pass
    finally:
        try:
            client_sock.close()
        except Exception:
            pass


def relay(sock1, sock2):
    """Bidirectional relay between two sockets."""
    def forward(src, dst):
        try:
            while True:
                data = src.recv(8192)
                if not data:
                    break
                dst.sendall(data)
        except Exception:
            pass
        finally:
            try:
                dst.shutdown(socket.SHUT_WR)
            except Exception:
                pass

    t1 = threading.Thread(target=forward, args=(sock1, sock2), daemon=True)
    t2 = threading.Thread(target=forward, args=(sock2, sock1), daemon=True)
    t1.start()
    t2.start()
    t1.join(timeout=300)
    t2.join(timeout=300)


def relay_one_way(src, dst):
    try:
        while True:
            data = src.recv(8192)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            src.close()
        except Exception:
            pass
        try:
            dst.close()
        except Exception:
            pass


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', LOCAL_PORT))
    server.listen(50)
    print(f'Local proxy listening on 127.0.0.1:{LOCAL_PORT}', flush=True)

    while True:
        client, addr = server.accept()
        t = threading.Thread(target=handle_client, args=(client,), daemon=True)
        t.start()


if __name__ == '__main__':
    main()
