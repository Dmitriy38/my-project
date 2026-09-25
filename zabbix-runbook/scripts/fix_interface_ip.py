#!/usr/bin/env python3
"""
V2: Дозаполняет поле IP в Agent-интерфейсе хостов — но перед этим
СВЕРЯЕТ DNS-имя интерфейса с уже собранным значением item "system.hostname"
(реальное имя компьютера по мнению Windows, а не то, что вручную вписано
в форму хоста Zabbix). Если не совпадает — НЕ пишет автоматически,
а помечает хост на ручную проверку (там явно ошибка в конфигурации
хоста, а не в резолвинге).

Требования: pip install requests --break-system-packages
"""

import socket
import requests

ZABBIX_URL = "http://10.**.**.**/zabbix/api_jsonrpc.php"  # TODO
API_TOKEN = "API_TOKEN"

HOST_GROUPS = [
    "network_AK", "network_ALN", "network_AN", "network_AN2",
    "network_BM", "network_EP", "network_GR", "network_IRK2",
    "network_KM", "network_KU", "network_LM", "network_LS",
    "network_MK", "network_PR", "network_VL", "network_YD",
    "network_office1", "network_office2",
]

SKIP_NAME_CONTAINS = ["mikrotik", "switch", "ubiquiti", "wifi", "poe_", "server"]
EXCLUDE_IF_IN_GROUPS = ["Kyocera"]

DRY_RUN = False


def api_call(method, params, auth_token=None):
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
    headers = {"Content-Type": "application/json-rpc"}
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
    resp = requests.post(ZABBIX_URL, json=payload, headers=headers, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    if "error" in data:
        raise RuntimeError(f"Zabbix API error on {method}: {data['error']}")
    return data["result"]


def get_hostname_value(hostid, token):
    """Возвращает последнее собранное значение item system.hostname для хоста, либо None."""
    items = api_call(
        "item.get",
        {
            "output": ["itemid", "value_type"],
            "hostids": [hostid],
            "search": {"key_": "system.hostname"},
        },
        token,
    )
    if not items:
        return None
    itemid = items[0]["itemid"]
    value_type = items[0]["value_type"]  # 1 = текстовый, для system.hostname обычно так
    history = api_call(
        "history.get",
        {
            "itemids": [itemid],
            "history": value_type,
            "sortfield": "clock",
            "sortorder": "DESC",
            "limit": 1,
        },
        token,
    )
    if not history:
        return None
    return history[0]["value"]


def main():
    token = API_TOKEN

    groups = api_call("hostgroup.get",
                       {"output": ["groupid"], "filter": {"name": HOST_GROUPS}}, token)
    group_ids = [g["groupid"] for g in groups]

    hosts = api_call(
        "host.get",
        {
            "output": ["hostid", "host", "name"],
            "groupids": group_ids,
            "selectInterfaces": ["interfaceid", "type", "ip", "dns", "useip"],
            "selectHostGroups": ["name"],
        },
        token,
    )

    print(f"Найдено хостов: {len(hosts)}")

    for host in hosts:
        hostname = host["name"]

        if any(s.lower() in hostname.lower() for s in SKIP_NAME_CONTAINS):
            continue

        group_names = [g["name"] for g in host.get("hostgroups", [])]
        if any(g.lower() in [x.lower() for x in group_names] for g in EXCLUDE_IF_IN_GROUPS):
            continue

        agent_iface = next((i for i in host["interfaces"] if i["type"] == "1"), None)
        if not agent_iface:
            continue

        if agent_iface["ip"]:
            continue  # IP уже заполнен ранее

        dns_name = agent_iface["dns"]
        if not dns_name:
            print(f"[SKIP: нет DNS-имени в интерфейсе] {hostname}")
            continue

        # --- Сверка с реальным именем компьютера по данным агента ---
        real_hostname = get_hostname_value(host["hostid"], token)
        if real_hostname is not None:
            # Сравниваем без учёта регистра; допускаем, что real_hostname
            # может быть полным FQDN, поэтому сравниваем начало строки
            if not real_hostname.lower().startswith(dns_name.lower()) and \
               not dns_name.lower().startswith(real_hostname.lower()):
                print(f"[ТРЕБУЕТ ПРОВЕРКИ ВРУЧНУЮ] {hostname}: "
                      f"DNS в интерфейсе = '{dns_name}', "
                      f"а system.hostname по факту = '{real_hostname}' — не совпадают!")
                continue
        else:
            print(f"[ПРЕДУПРЕЖДЕНИЕ: нет данных system.hostname, сверить не с чем] {hostname}")
            # Продолжаем по DNS без сверки — при желании можно continue
            # вместо этого, если хотите быть ещё строже:
            # continue

        try:
            resolved_ip = socket.gethostbyname(dns_name)
        except socket.gaierror:
            print(f"[ОШИБКА: не удалось зарезолвить '{dns_name}'] {hostname}")
            continue

        print(f"[{'DRY-RUN' if DRY_RUN else 'APPLY'}] {hostname}: "
              f"дописываю IP {resolved_ip} (DNS: {dns_name})")

        if DRY_RUN:
            continue

        api_call(
            "hostinterface.update",
            {"interfaceid": agent_iface["interfaceid"], "ip": resolved_ip},
            token,
        )

    print("\nЭто был DRY_RUN — ничего не изменено." if DRY_RUN else "\nГотово.")


if __name__ == "__main__":
    main()
