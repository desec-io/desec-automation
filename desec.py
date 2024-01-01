import socket
import logging
import ssl
import re
import time
import threading

from tqdm import tqdm 

import dns.message
import dns.query
import dns.exception
import dns.rcode
import dns.name
import pandas as pd

logging.basicConfig(level=logging.WARNING)

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

NS = [m[0] for m in re.finditer(r'[^\s\"]+\.[ac]\.desec\.io', "\n".join(list(open('hosts/all.yml', 'r'))))] + ['ns1.desec.io', 'ns2.desec.org']

NS_NET = {
    'ams-1.a.desec.io': 'a1',
    'dfw-1.a.desec.io': 'a1',
    'fra-1.a.desec.io': 'a2',
    'hkg-1.a.desec.io': 'a2',
    'jnb-1.a.desec.io': 'a2',
    'sao-1.a.desec.io': 'a1',
    'syd-1.a.desec.io': 'a2',
    'dxb-1.c.desec.io': 'c1',
    'fra-1.c.desec.io': 'c1',
    'lax-1.c.desec.io': 'c1',
    'lga-1.c.desec.io': 'c2',
    'lhr-1.c.desec.io': 'c2',
    'scl-1.c.desec.io': 'c2',
    'sin-1.c.desec.io': 'c1',
    'tyo-1.c.desec.io': 'c2',
    'ns1.desec.io': 'ns1',
    'ns2.desec.org': 'ns2',
}

assert set(NS) == set(NS_NET.keys())

def query_all():
    
    threads = {}
    responses = []

    def work(ns, qname, qtype, addr, query):
        response = {
            'ns': ns,
            'addr': addr,
            'transport': query.__name__,
        }

        try:
            logging.debug(f"Query {qname}/{qtype} at {ns}/{addr} using {query.__name__}")

            q = dns.message.make_query(qname, qtype)
            response['query'] = q

            match query:
                case dns.query.quic:
                    kwargs = dict(verify=False, timeout=3)
                case dns.query.tls:
                    kwargs = dict(ssl_context=ssl_context, timeout=3)
                case _:
                    kwargs = dict(timeout=1)

            response['sent'] = time.time()
            r = query(q, where=addr, **kwargs)
            response['received'] = time.time()

            responses.append(response | {'response': r})

        except Exception as ex:
            logging.debug(f"Query {qname}/{qtype} at {ns}/{addr} using {query.__name__}: {ex}")
            responses.append(response | {'error': ex})

    for ns in NS:
        for qname in ['external-timestamp.desec.test']:
            for qtype in ['TXT']:
                for addr in {sockaddr[0] for (_, _, _, _, sockaddr) in socket.getaddrinfo(ns, 53)}:
                    if ('.a.' in ns or '.c.' in ns) and ':' in addr:
                        logging.debug(f"Skipping v6 addr for {ns} ({addr})")
                        continue
                    for query in [dns.query.udp, dns.query.tcp, dns.query.tls, dns.query.quic]:
                        if query == dns.query.quic and ns in ['ns1.desec.io', 'ns2.desec.org']:
                            continue
                        t = threading.Thread(target=work, args=(ns, qname, qtype, addr, query))
                        threads[(ns, qname, qtype, addr, query)] = t
                        t.start()

    for (ns, qname, qtype, addr, query), t in threads.items():
        t.join(timeout=3)

    return responses

def replication_status():
    data = pd.DataFrame(query_all())
    data['qname'] = data['query'].apply(lambda q: q.question[0].name.to_text())
    data['qtype'] = data['query'].apply(lambda q: q.question[0].rdtype)
    data['ip'] = data['addr'].apply(lambda addr: 4 if '.' in addr else 6)
    data['rcode'] = data['response'].apply(lambda r: dns.rcode.to_text(r.rcode()) if not pd.isna(r) else None)
    data['response_data'] = data['response'].apply(lambda r: int(r.answer[0][0].to_text().strip("\"")) if not pd.isna(r) else None)
    data['ns_net'] = data['ns'].apply(lambda ns: NS_NET[ns])
    data['lag'] = data['response_data'] - data['received']
    return data

def replication_rcodes(data):
    return data.sort_values(['ns_net', 'ns']).pivot(index=('ns_net', 'ns', 'addr'), columns='transport', values='rcode')

def replication_lag(data):
    return data.sort_values(['ns_net', 'ns']).pivot(index=('ns_net', 'ns', 'addr'), columns='transport', values='lag')
