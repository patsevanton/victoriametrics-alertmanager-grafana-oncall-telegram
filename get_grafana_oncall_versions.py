import requests

# URL-эндпоинт для получения сведений о plugin
plugin_slug = "grafana-oncall-app"
url = f"https://grafana.com/api/plugins/{plugin_slug}"

response = requests.get(url)
data = response.json()

# Вся информация о версиях хранится в поле 'versions' (список словарей)
versions = data.get("versions", [])
version_list = [version["version"] for version in versions]

# Выводим список версий
print("Доступные версии Grafana OnCall:")
for v in version_list:
    print(v)
