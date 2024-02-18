#!/usr/bin/env python3

import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import argparse
from datetime import datetime

def send_email(smtp_server, port, ssl_mode, username, password, from_addr, to_addrs, subject, body, attachments):
    if ssl_mode == "ssl":
        context = ssl.create_default_context()
        server = smtplib.SMTP_SSL(smtp_server, port, context=context)
    elif ssl_mode == "starttls":
        server = smtplib.SMTP(smtp_server, port)
        server.starttls(context=ssl.create_default_context())  # Upgrade the connection to SSL/TLS
    else:
        server = smtplib.SMTP(smtp_server, port)

    if username and password:
        server.login(username, password)

    msg = MIMEMultipart()
    msg['From'] = from_addr
    msg['To'] = ', '.join(to_addrs)
    msg['Subject'] = subject
    msg['Date'] = datetime.now().strftime('%a, %d %b %Y %H:%M:%S +0000')

    msg.attach(MIMEText(body, 'plain'))

    for attachment in attachments:
        with open(attachment, 'rb') as file:
            part = MIMEBase('application', 'octet-stream')
            part.set_payload(file.read())
            encoders.encode_base64(part)
            part.add_header('Content-Disposition', f'attachment; filename={attachment}')
            msg.attach(part)

    server.sendmail(from_addr, to_addrs, msg.as_string())
    server.quit()

def main():
    parser = argparse.ArgumentParser(description='Send an email via SMTP with optional SSL/TLS.')
    parser.add_argument('--server', required=True, help='SMTP server address.')
    parser.add_argument('--port', type=int, default=587, help='SMTP server port (default: 587).')
    parser.add_argument('--ssl-mode', choices=['none', 'starttls', 'ssl'], default='none', help='Use SSL/TLS to connect to the SMTP server.')

    parser.add_argument('--username', help='Username for SMTP authentication.')
    parser.add_argument('--password', help='Password for SMTP authentication.')
    parser.add_argument('--from', dest='from_addr', required=True, help='The email sender address.')
    parser.add_argument('--to', nargs='+', required=True, help='The email recipient addresses.')
    parser.add_argument('--subject', default='No Subject', help='Email subject.')
    parser.add_argument('--body', default='', help='Email body.')
    parser.add_argument('--attachments', nargs='*', default=[], help='Paths to files to attach.')

    args = parser.parse_args()

    send_email(
        smtp_server=args.server,
        port=args.port,
        ssl_mode=args.ssl_mode,
        username=args.username,
        password=args.password,
        from_addr=args.from_addr,
        to_addrs=args.to,
        subject=args.subject,
        body=args.body,
        attachments=args.attachments
    )

if __name__ == '__main__':
    main()