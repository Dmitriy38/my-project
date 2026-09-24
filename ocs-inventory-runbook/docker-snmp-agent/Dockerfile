FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget ca-certificates make gcc \
        libmodule-install-perl dmidecode \
        libxml-simple-perl libcompress-zlib-perl openssl \
        libnet-ip-perl libwww-perl libdigest-md5-perl \
        libdata-uuid-perl libcrypt-ssleay-perl libnet-snmp-perl \
        libproc-pid-file-perl libproc-daemon-perl net-tools \
        libsys-syslog-perl pciutils nmap arp-scan iproute2 libnet-netmask-perl \
        libcrypt-des-perl libcrypt-rijndael-perl libdigest-hmac-perl \
    && rm -rf /var/lib/apt/lists/*

ARG AGENT_VERSION=2.10.5

WORKDIR /usr/src
RUN wget "https://github.com/OCSInventory-NG/UnixAgent/releases/download/v${AGENT_VERSION}/Ocsinventory-Unix-Agent-${AGENT_VERSION}.tar.gz" \
    && tar xzf "Ocsinventory-Unix-Agent-${AGENT_VERSION}.tar.gz" \
    && cd "Ocsinventory-Unix-Agent-${AGENT_VERSION}" \
    && env PERL_AUTOINSTALL=1 perl Makefile.PL \
    && make \
    && make install \
    && perl postinst.pl --nowizard --server=http://localhost/ocsinventory --snmp --tag=SNMP-COLLECTOR

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
