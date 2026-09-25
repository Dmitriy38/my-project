#!/usr/bin/env python3
"""
Находит хосты, у которых "Имя узла сети" — это голый IP-адрес
(например "10.38.29.169"), и переименовывает их в реальное имя
компьютера, которое уже сообщает сам агент через item system.hostname
("System name" в интерфейсе, как на вашем скриншоте).

Если хост с таким именем уже существует (реальный дубль-конфликт) —
УДАЛЯЕТ дублирующий хост с именем-IP.

Требования: pip install requests --break-system-packages
"""

import re
import requests

ZABBIX_URL = "http://10.**.**.**/zabbix/api_jsonrpc.php"  # TODO
API_TOKEN = "API_TOKEN"

IP_NAME_PATTERN = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")

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
    """Последнее собранное значение item system.hostname (System name) для хоста."""
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
    value_type = items[0]["value_type"]
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
    return history[0]["value"].strip()


def main():
    token = API_TOKEN

    all_hosts = api_call(
        "host.get",
        {"output": ["hostid", "host", "name"]},
        token,
    )

    ip_hosts = [h for h in all_hosts if IP_NAME_PATTERN.match(h["name"])]
    all_names = {h["host"].lower() for h in all_hosts}

    print(f"Найдено хостов с именем в виде IP: {len(ip_hosts)}")

    for host in ip_hosts:
        current_name = host["name"]
        real_name = get_hostname_value(host["hostid"], token)

        if not real_name:
            print(f"[SKIP: нет данных system.hostname] {current_name}")
            continue

        # ОБНОВЛЕННЫЙ БЛОК: Удаление дубликата вместо пропуска
        if real_name.lower() in all_names and real_name.lower() != current_name.lower():
            print(f"[{'DRY-RUN' if DRY_RUN else 'УДАЛЕНИЕ'}] Хост '{real_name}' уже существует. Удаляю дубликат с IP: {current_name}")
            
            if not DRY_RUN:
                try:
                    # Метод host.delete принимает массив ID хостов
                    api_call("host.delete", [host["hostid"]], token)
                    print(f"  -> Успешно удален: {current_name}")
                except Exception as e:
                    print(f"  -> [ОШИБКА] Не удалось удалить {current_name}: {e}")
            
            continue

        print(f"[{'DRY-RUN' if DRY_RUN else 'APPLY'}] {current_name} -> {real_name}")

        if DRY_RUN:
            continue

        api_call(
            "host.update",
            {"hostid": host["hostid"], "host": real_name, "name": real_name},
            token,
        )

    print("\nЭто был DRY_RUN — ничего не изменено." if DRY_RUN else "\nГотово.")


if __name__ == "__main__":
    main()
